// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../access/AccessHelper.sol';
import './interfaces/IManagedPriceRouter.sol';
import './interfaces/IPriceFeedChainlinkV3.sol';
import './interfaces/IPriceFeedUniswapV2.sol';
import './PriceSourceBase.sol';

// @dev All prices given out have 18 decimals
abstract contract OracleRouterBase is IManagedPriceRouter, AccessHelper, PriceSourceBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  address private immutable _quote;

  constructor(address quote) {
    _quote = quote;
  }

  function _onlyOracleAdmin() private view {
    if (!hasAnyAcl(msg.sender, AccessFlags.PRICE_ROUTER_ADMIN)) {
      revert Errors.CallerNotOracleAdmin();
    }
  }

  modifier onlyOracleAdmin() {
    _onlyOracleAdmin();
    _;
  }

  uint8 private constant CF_UNISWAP_V2_RESERVE = 1 << 0;

  /// @inheritdoc IFallbackPriceOracle
  function getQuoteAsset() public view returns (address) {
    return _quote;
  }

  /// @inheritdoc IFallbackPriceOracle
  function getAssetPrice(address asset) public view override returns (uint256) {
    if (asset == _quote) {
      return WadRayMath.WAD;
    }

    (uint256 v, ) = internalReadSource(asset);

    if (v == 0) {
      revert Errors.UnknownPriceAsset(asset);
    }

    return v;
  }

  /// @inheritdoc IPriceRouter
  function getAssetPrices(address[] calldata assets) external view override returns (uint256[] memory result) {
    result = new uint256[](assets.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      result[i] = getAssetPrice(assets[i]);
    }
    return result;
  }

  error UnknownPriceFeedType(uint8);

  function internalGetHandler(uint8 callType)
    internal
    pure
    override
    returns (function(uint8, address, address) internal view returns (uint256, uint32))
  {
    if (callType == uint8(PriceFeedType.ChainLinkV3)) {
      return _readChainlink;
    } else if (callType == uint8(PriceFeedType.UniSwapV2Pair)) {
      return _readUniswapV2;
    }
    revert UnknownPriceFeedType(callType);
  }

  function _readChainlink(
    uint8,
    address feed,
    address
  ) private view returns (uint256, uint32) {
    (, int256 v, , uint256 at, ) = IPriceFeedChainlinkV3(feed).latestRoundData();
    return (uint256(v), uint32(at));
  }

  function _readUniswapV2(
    uint8 callFlags,
    address feed,
    address
  ) private view returns (uint256 v0, uint32 at) {
    uint256 v1;
    (v0, v1, at) = IPriceFeedUniswapV2(feed).getReserves();
    if (v0 != 0) {
      if (callFlags & CF_UNISWAP_V2_RESERVE != 0) {
        (v0, v1) = (v1, v0);
      }
      v0 = v1.wadDiv(v0);
    }
  }

  // slither-disable-next-line calls-loop
  function _setupUniswapV2(address feed, address token) private view returns (uint8 callFlags) {
    if (token == IPriceFeedUniswapV2(feed).token1()) {
      return CF_UNISWAP_V2_RESERVE;
    }
    Value.require(token == IPriceFeedUniswapV2(feed).token0());
  }

  function _getPriceSource(address asset, PriceSource memory result)
    private
    view
    returns (
      bool ok,
      uint8 decimals,
      address crossPrice,
      uint32 maxValidity,
      uint8 flags
    )
  {
    bool staticPrice;
    (ok, decimals, crossPrice, maxValidity, flags, staticPrice) = internalGetConfig(asset);

    if (ok) {
      result.decimals = decimals;
      result.crossPrice = crossPrice;
      // result.maxValidity = maxValidity;

      if (staticPrice) {
        result.feedType = PriceFeedType.StaticValue;
        (result.feedConstValue, ) = internalGetStatic(asset);
      } else {
        uint8 callType;
        (callType, result.feedContract, , , ) = internalGetSource(asset);
        result.feedType = PriceFeedType(callType);
      }
    }
  }

  /// @inheritdoc IManagedPriceRouter
  function getPriceSource(address asset) external view returns (PriceSource memory result) {
    _getPriceSource(asset, result);
  }

  /// @inheritdoc IManagedPriceRouter
  function getPriceSources(address[] calldata assets) external view returns (PriceSource[] memory result) {
    result = new PriceSource[](assets.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _getPriceSource(assets[i], result[i]);
    }
  }

  /// @inheritdoc IManagedPriceRouter
  function setPriceSources(address[] calldata assets, PriceSource[] calldata sources) external onlyOracleAdmin {
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _setPriceSource(assets[i], sources[i]);
    }
  }

  /// @inheritdoc IManagedPriceRouter
  function setStaticPrices(address[] calldata assets, uint256[] calldata prices) external onlyOracleAdmin {
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _setStaticValue(assets[i], prices[i]);
    }
  }

  event SourceStaticUpdated(address indexed asset, uint256 value);
  event SourceStaticConfigured(address indexed asset, uint256 value, uint8 decimals, address xPrice);
  event SourceFeedConfigured(address indexed asset, address source, uint8 decimals, address xPrice, uint8 feedType, uint8 callFlags);

  function _setStaticValue(address asset, uint256 value) private {
    Value.require(asset != _quote);

    internalSetStatic(asset, value, 0);
    emit SourceStaticUpdated(asset, value);
  }

  function _setPriceSource(address asset, PriceSource calldata source) private {
    Value.require(asset != _quote);

    if (source.feedType == PriceFeedType.StaticValue) {
      internalSetStatic(asset, source.feedConstValue, 0);

      emit SourceStaticConfigured(asset, source.feedConstValue, source.decimals, source.crossPrice);
    } else {
      uint8 callFlags;
      if (source.feedType == PriceFeedType.UniSwapV2Pair) {
        callFlags = _setupUniswapV2(source.feedContract, asset);
      }
      internalSetSource(asset, uint8(source.feedType), source.feedContract, callFlags);

      emit SourceFeedConfigured(asset, source.feedContract, source.decimals, source.crossPrice, uint8(source.feedType), callFlags);
    }
    internalSetConfig(asset, source.decimals, source.crossPrice, 0);
  }

  event PriceRangeUpdated(address indexed asset, uint256 targetPrice, uint16 tolerancePct);

  /// @inheritdoc IManagedPriceRouter
  function setSafePriceRanges(
    address[] calldata assets,
    uint256[] calldata targetPrices,
    uint16[] calldata tolerancePcts
  ) external override onlyOracleAdmin {
    Value.require(assets.length == targetPrices.length);
    Value.require(assets.length == tolerancePcts.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      address asset = assets[i];
      Value.require(asset != address(0) && asset != _quote);

      uint256 targetPrice = targetPrices[i];
      uint16 tolerancePct = tolerancePcts[i];

      internalSetPriceTolerance(asset, targetPrice, tolerancePct);
      emit PriceRangeUpdated(asset, targetPrice, tolerancePct);
    }
  }

  /// @inheritdoc IManagedPriceRouter
  function getPriceSourceRange(address asset) external view override returns (uint256 targetPrice, uint16 tolerancePct) {
    (, , , targetPrice, tolerancePct) = internalGetSource(asset);
  }

  event SourceGroupResetted(address indexed account, uint256 mask);

  /// @inheritdoc IManagedPriceRouter
  function resetSourceGroupByAdmin(uint256 mask) external override onlyOracleAdmin {
    internalResetGroup(mask);
    emit SourceGroupResetted(address(0), mask);
  }

  function internalResetGroup(uint256 mask) internal virtual;

  function internalRegisterGroup(address account, uint256 mask) internal virtual;

  event SourceGroupConfigured(address indexed account, uint256 mask);

  /// @inheritdoc IManagedPriceRouter
  function configureSourceGroup(address account, uint256 mask) external override onlyOracleAdmin {
    Value.require(account != address(0));
    internalRegisterGroup(account, mask);
    emit SourceGroupConfigured(account, mask);
  }

  function groupsOf(address) external view virtual returns (uint256 memberOf, uint256 ownerOf);
}
