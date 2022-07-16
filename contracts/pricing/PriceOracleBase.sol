// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../access/AccessHelper.sol';
import './interfaces/IManagerPriceOracle.sol';
import './interfaces/IPriceFeedChainlinkV3.sol';
import './interfaces/IPriceFeedUniswapV2.sol';
import './PriceSourceBase.sol';
import './FuseBox.sol';

abstract contract PriceOracleBase is IManagerPriceOracle, AccessHelper, PriceSourceBase, FuseBox {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  function _onlyOracleAdmin() private view {
    if (!hasAnyAcl(msg.sender, AccessFlags.ORACLE_ADMIN)) {
      revert Errors.CalllerNotOracleAdmin();
    }
  }

  modifier onlyOracleAdmin() {
    _onlyOracleAdmin();
    _;
  }

  uint8 private constant RF_FUSED = 1 << 0;
  uint8 private constant RF_UNISWAP_V2_RESERVE = 1 << 1;

  function pullAssetPrice(address asset, uint256 fuseMask) public returns (uint256) {
    (uint256 v, uint8 flags) = internalReadSource(asset);

    if (v == 0) {
      revert Errors.UnknownPriceAsset(asset);
    }

    if (internalHasAnyBlownFuse(fuseMask)) {
      revert Errors.ExcessiveVolatilityLock(fuseMask);
    }

    if (flags & RF_LIMIT_BREACHED != 0) {
      if (flags & RF_FUSED != 0) {
        internalBlowFuses(asset);
      } else {
        revert Errors.ExcessiveVolatility();
      }
    }

    return v;
  }

  function getAssetPrice(address asset) public view override returns (uint256) {
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
    uint8 flags,
    address feed,
    address
  ) private view returns (uint256 v0, uint32 at) {
    uint256 v1;
    (v0, v1, at) = IPriceFeedUniswapV2(feed).getReserves();
    if (v0 != 0) {
      if (flags & RF_UNISWAP_V2_RESERVE == 1) {
        (v0, v1) = (v1, v0);
      }
      v0 = v1.wadDiv(v0);
    }
  }

  // function getPriceSource(address asset) public view override returns (PriceSource memory) {
  //   Source storage src = _sources[asset];
  //   return PriceSource(src.source, src.staticPrice, src.sourceType);
  // }

  // function getPriceSources(address[] calldata assets) external view override returns (PriceSource[] memory result) {
  //   result = new PriceSource[](assets.length);
  //   for (uint256 i = assets.length; i > 0; ) {
  //     i--;
  //     result[i] = getPriceSource(assets[i]);
  //   }
  //   return result;
  // }

  function setPriceSources(address[] calldata assets, PriceSource[] calldata sources) external onlyOracleAdmin {
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      PriceFeedType ft = sources[i].feedType;
      if (ft == PriceFeedType.StaticValue) {
        _setStaticValue(assets[i], sources[i].feedConstValue);
      } else {
        _setPriceSource(assets[i], uint8(ft), sources[i].feedContract);
      }
    }
  }

  // function _setPriceSource(
  //   address asset,
  //   address weth,
  //   Source memory src
  // ) private {
  //   require(asset != weth);
  //   if (src.sourceType != PriceSourceType.Chainlink) {
  //     require(src.source != address(0));
  //     // TODO src.flags =
  //   }
  //   _sources[asset] = src;
  // }

  // function setStaticPrices(address[] calldata assets, uint256[] calldata prices) external override onlyOracleAdmin {
  //   for (uint256 i = assets.length; i > 0; ) {
  //     i--;
  //     require(assets[i] != WETH);
  //     require(prices[i] <= type(uint224).max);
  //     _sources[assets[i]].staticPrice = uint224(prices[i]);
  //   }
  // }

  function _setStaticValue(address asset, uint256 value) private {
    internalSetStatic(asset, value, 0);
  }

  function _setPriceSource(
    address asset,
    uint8 feedType,
    address feedContract
  ) private {
    internalSetSource(asset, feedType, feedContract);
  }
}
