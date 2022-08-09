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
import './FuseBox.sol';

// @dev All prices given out have 18 decimals
abstract contract OracleRouterBase is IManagedPriceRouter, AccessHelper, PriceSourceBase, FuseBox {
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

  function getQuoteAsset() public view returns (address) {
    return _quote;
  }

  function pullAssetPrice(address asset, uint256 fuseMask) external override returns (uint256) {
    if (asset == _quote) {
      return WadRayMath.WAD;
    }

    (uint256 v, uint8 flags) = internalReadSource(asset);

    if (v == 0) {
      revert Errors.UnknownPriceAsset(asset);
    }

    if (internalHasAnyBlownFuse(fuseMask)) {
      revert Errors.ExcessiveVolatilityLock(fuseMask);
    }

    if (flags & EF_LIMIT_BREACHED != 0) {
      if (!internalBlowFuses(asset)) {
        revert Errors.ExcessiveVolatility();
      }
    }

    return v;
  }

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

  function getPriceSource(address asset) external view returns (PriceSource memory result) {
    _getPriceSource(asset, result);
  }

  function getPriceSources(address[] calldata assets) external view returns (PriceSource[] memory result) {
    result = new PriceSource[](assets.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _getPriceSource(assets[i], result[i]);
    }
  }

  /// @param sources  If using a Uniswap price, the decimals field must compensate for tokens that
  ///                 do not have the same as the quote asset decimals.
  ///                 If the quote asset has 18 decimals:
  ///                   If a token has 9 decimals, it must set the decimals value to (9 + 18) = 27
  ///                   If a token has 27 decimals, it must set the decimals value to (27 - 18) = 9
  function setPriceSources(address[] calldata assets, PriceSource[] calldata sources) external onlyOracleAdmin {
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _setPriceSource(assets[i], sources[i]);
    }
  }

  /// @dev When an asset was configured before, then this call assumes the price to have same decimals, otherwise 18
  function setStaticPrices(address[] calldata assets, uint256[] calldata prices) external onlyOracleAdmin {
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _setStaticValue(assets[i], prices[i]);
    }
  }

  function _setStaticValue(address asset, uint256 value) private {
    internalSetStatic(asset, value, 0);
  }

  function _setPriceSource(address asset, PriceSource calldata source) private {
    if (source.feedType == PriceFeedType.StaticValue) {
      _setStaticValue(asset, source.feedConstValue);
    } else {
      uint8 callFlags;
      if (source.feedType == PriceFeedType.UniSwapV2Pair) {
        callFlags = _setupUniswapV2(source.feedContract, asset);
      }
      internalSetSource(asset, uint8(source.feedType), source.feedContract, callFlags);
    }
    internalSetConfig(asset, source.decimals, source.crossPrice, 0);
  }

  function setPriceSourceRange(
    address asset,
    uint256 targetPrice,
    uint16 tolerancePct
  ) external override onlyOracleAdmin {
    Value.require(asset != address(0));

    internalSetPriceTolerance(asset, targetPrice, tolerancePct);
  }

  function getPriceSourceRange(address asset) external view override returns (uint256 targetPrice, uint16 tolerancePct) {
    (, , , targetPrice, tolerancePct) = internalGetSource(asset);
  }

  function attachSource(address asset, bool attach) external override {
    Value.require(asset != address(0));

    uint256 maskUnset = internalGetOwnedFuses(msg.sender);
    uint256 maskSet;
    Access.require(maskUnset != 0);

    if (attach) {
      (maskSet, maskUnset) = (maskUnset, 0);
    }
    internalSetFuses(asset, maskUnset, maskSet);
  }

  function resetSourceGroup() external override {
    uint256 mask = internalGetOwnedFuses(msg.sender);
    if (mask != 0) {
      internalResetFuses(mask);
    }
  }

  function resetSourceGroupByAdmin(uint256 mask) external override onlyOracleAdmin {
    internalResetFuses(mask);
  }

  function registerSourceGroup(
    address account,
    uint256 mask,
    bool register
  ) external override onlyOracleAdmin {
    Value.require(account != address(0));

    internalSetOwnedFuses(account, register ? mask : 0);
  }

  function groupsOf(address account) external view returns (uint256 memberOf, uint256 ownerOf) {
    return (internalGetFuses(account), internalGetOwnedFuses(account));
  }
}
