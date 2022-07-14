// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import './interfaces/IManagerPriceOracle.sol';

abstract contract PriceOracle is IManagerPriceOracle {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  // solhint-disable-next-line var-name-mixedcase
  address private _fallback;

  struct Source {
    address source; // uint160
    int8 decimalDiff;
    PriceSourceType sourceType; // static / direct / rebase / expiry / tolerance+target
    uint224 staticPrice;
    uint16 flags;
  }

  struct ActiveSource {
    uint8 flags;
    // int6 decimalDiff;
    // uint2 crossPrice;
    uint8 maxValidity; // minutes
    uint8 callType;
    address source;

    // uint56 target;
    // uint8 tolerance;
  }

  struct StaticSource {
    uint8 flags;
    // uint6 decimals;
    // uint2 crossPrice;
    uint8 maxValidity; // minutes
    // uint32 updatedAt;
    // uint200 static
  }

  mapping(address => uint256) private _encodedSources;
  mapping(uint8 => address) private _crossTokens;

  uint8 private constant SRC_CONFIG_BITS = 24;

  uint8 private constant SF_STATIC = 1 << 0;
  uint8 private constant SF_CROSS_PRICED = 1 << 1;

  function _readSource(address token) private returns (uint256) {
    uint256 encoded = _encodedSources[token];
    if (encoded == 0) {
      return 0;
    }

    uint8 flags = uint8(encoded);

    encoded >>= 8;
    uint8 decimals = uint8(encoded);

    encoded >>= 8;
    uint8 maxValidity = uint8(encoded);

    encoded >>= 8;
    (uint256 v, uint32 t) = flags & SF_STATIC == 0
      ? _callSource(flags, uint8(encoded), address(uint160(encoded >> 8)), token)
      : (encoded >> 32, uint32(encoded));

    require(maxValidity == 0 || t == 0 || t + maxValidity * 1 minutes >= block.timestamp);

    if (flags & SF_CROSS_PRICED != 0) {
      v *= _readSource(_crossTokens[uint8(decimals & 3)]);
    }

    if ((decimals >>= 2) != 18) {
      if (decimals < 18) {
        v *= 10**uint8(18 - decimals);
      } else {
        v /= 10**uint8(decimals - 18);
      }
    }

    if (flags & SF_CROSS_PRICED != 0) {
      v = v.divUp(WadRayMath.WAD);
    }

    if (SF_STATIC != 0 && encoded > 0 && _checkTolerance(v, encoded)) {
      handlePriceBeach(token, v);
    }

    return v;
  }

  uint256 private constant TARGET_UNIT = 10**9;
  uint256 private constant TOLERANCE_ONE = 800;

  function _checkTolerance(uint256 v, uint256 target) private pure returns (bool) {
    uint8 tolerance = uint8(target);
    target >>= 8;
    target *= TARGET_UNIT;

    v = v > target ? v - target : target - v;
    return (v * TOLERANCE_ONE > target * tolerance);
  }

  function _callSource(
    uint8 flags,
    uint8 callType,
    address feed,
    address token
  ) private returns (uint256 v, uint32 t) {}

  function handlePriceBeach(address token, uint256 price) internal virtual {}

  function internalSetStatic(
    address token,
    uint256 value,
    uint32 since
  ) private {
    uint256 encoded = _encodedSources[token];
    require(value <= type(uint200).max);

    if (since == 0 && value != 0) {
      since = uint32(block.timestamp);
    }

    value = (value << 32) | since;
    _encodedSources[token] = (value << SRC_CONFIG_BITS) | uint24(encoded) | SF_STATIC;
  }

  uint256 private constant SRC_SOURCE_BITS = 168;
  uint256 private constant SF_SOURCE_INV_MASK = ~(uint256(type(uint168).max) << SRC_CONFIG_BITS);

  function internalSetSource(
    address token,
    uint8 callType,
    address feed
  ) private {
    if (feed == address(0)) {
      Value.require(callType == 0);
      delete _encodedSources[token];
      return;
    }
    // TODO check callType

    uint256 encoded = _encodedSources[token];
    if (encoded & SF_STATIC != 0) {
      encoded = uint24(encoded) ^ SF_STATIC;
    } else {
      encoded &= SF_SOURCE_INV_MASK;
    }

    encoded |= ((uint256(callType) << 160) | uint160(feed)) << SRC_CONFIG_BITS;

    _encodedSources[token] = encoded;
  }

  uint256 private constant SF_SOURCE_AND_CONFIG_BITS = SRC_CONFIG_BITS + SRC_SOURCE_BITS;
  uint256 private constant SF_SOURCE_AND_CONFIG_INV_MASK = type(uint256).max >> (256 - SF_SOURCE_AND_CONFIG_BITS);

  function internalSetPriceTolerance(
    address token,
    uint256 targetPrice,
    uint16 tolerancePct
  ) private {
    uint256 encoded = _encodedSources[token];
    State.require(encoded & SF_STATIC == 0);

    uint256 v;
    if (targetPrice != 0) {
      v = uint256(tolerancePct).percentMul(TOLERANCE_ONE);
      Value.require(v <= type(uint8).max);

      targetPrice = targetPrice.divUp(TARGET_UNIT);
      Value.require(targetPrice > 0);
      v = (v << 56) | targetPrice;

      v <<= SF_SOURCE_AND_CONFIG_BITS;
    }

    _encodedSources[token] = v | (encoded & SF_SOURCE_AND_CONFIG_INV_MASK);
  }

  function _crossPriceIndex(address crossPrice) private view returns (uint8 index) {
    uint256 encoded = _encodedSources[crossPrice];

    Value.require(encoded != 0);
    State.require(encoded & SF_CROSS_PRICED == 0);
    index = uint8(encoded >> 8) & 3;

    State.require(_crossTokens[index] == crossPrice);
  }

  uint256 private constant SRC_CONFIG_BITS_NO_FLAGS = SRC_CONFIG_BITS ^ type(uint8).max;

  function internalSetConfig(
    address token,
    uint8 decimals,
    address crossPrice,
    uint32 maxValidity
  ) private {
    Value.require(decimals <= 63);
    decimals <<= 2;

    uint256 encoded = _encodedSources[token];
    State.require(encoded != 0);

    maxValidity = maxValidity == type(uint32).max ? 0 : (maxValidity + 1 minutes - 1) / 1 minutes;
    Value.require(maxValidity <= type(uint8).max);

    if (crossPrice != address(0)) {
      decimals |= _crossPriceIndex(crossPrice);
      encoded |= SF_CROSS_PRICED;
    } else {
      encoded &= ~uint256(SF_CROSS_PRICED);
    }

    _encodedSources[token] = (encoded & SRC_CONFIG_BITS_NO_FLAGS) | (uint256(maxValidity) << 16) | (uint256(decimals) << 8);
  }

  function internalGetConfig(address token)
    private
    view
    returns (
      bool ok,
      uint8 decimals,
      address crossPrice,
      uint32 maxValidity,
      bool staticPrice
    )
  {
    uint256 encoded = _encodedSources[token];
    if (encoded != 0) {
      ok = true;
      staticPrice = encoded & SF_STATIC != 0;

      uint8 flags = uint8(encoded);
      encoded >>= 8;
      decimals = uint8(encoded);

      crossPrice = _crossTokens[decimals & 3];
      if (crossPrice != address(0) && crossPrice != token && flags & SF_CROSS_PRICED == 0) {
        crossPrice = address(0);
      }

      decimals >>= 2;

      maxValidity = uint8(encoded >> 8);
    }
  }

  function internalGetSource(address token)
    private
    view
    returns (
      uint8 callType,
      address feed,
      uint256 target,
      uint16 tolerance
    )
  {
    uint256 encoded = _encodedSources[token];
    if (encoded != 0) {
      State.require(encoded & SF_STATIC == 0);
      encoded >>= SRC_CONFIG_BITS;
      callType = uint8(encoded);

      encoded >>= 8;
      feed = address(uint160(encoded));

      encoded >>= 160;
      target = uint56(encoded);
      target *= TARGET_UNIT;

      encoded >>= 56;
      tolerance = uint16(encoded.percentDiv(TOLERANCE_ONE));
    }
  }

  function internalGetStatic(address token) private view returns (uint256, uint32) {
    uint256 encoded = _encodedSources[token];
    State.require(encoded & SF_STATIC != 0);
    encoded >>= SRC_CONFIG_BITS;

    return (encoded >> 32, uint32(encoded));
  }

  // mapping(address => Source) private _sources;

  // constructor(
  //   address fallback_,
  //   address[] memory assets,
  //   PriceSource[] memory sources
  // ) {
  //   _fallback = fallback_;

  //   for (uint256 i = assets.length; i > 0; ) {
  //     i--;
  //     _setPriceSource(assets[i], weth, Source(sources[i].source, sources[i].staticPrice, sources[i].sourceType, 0));
  //   }
  // }

  modifier onlyOracleAdmin() {
    _;
  }

  // function getAssetPrice(address asset) public view override returns (uint256 v) {
  //   if ((v = _readSource(asset)) != 0) {
  //     return v;
  //   }
  //   IFallbackPriceOracle fb = IFallbackPriceOracle(_fallback);
  //   if (address(fb) != address(0) && (v = fb.getAssetPrice(asset)) != 0) {
  //     return v;
  //   }
  //   revert('UNKNOWN_PRICE');
  // }

  // function _getAssetPriceChainlink(address source) private view returns (uint256) {
  //   source;
  //   this;
  //   return 0;
  // }

  // function _getAssetPriceUniV2EthPair(address source, uint16 flags) private view returns (uint256) {
  //   source;
  //   flags;
  //   this;
  //   return 0;
  // }

  // function getAssetPrices(address[] calldata assets) external view override returns (uint256[] memory result) {
  //   result = new uint256[](assets.length);
  //   for (uint256 i = assets.length; i > 0; ) {
  //     i--;
  //     result[i] = getAssetPrice(assets[i]);
  //   }
  //   return result;
  // }

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

  // function setPriceSources(address[] calldata assets, PriceSource[] calldata sources) external override onlyOracleAdmin {
  //   address weth = WETH;
  //   for (uint256 i = assets.length; i > 0; ) {
  //     i--;
  //     _setPriceSource(assets[i], weth, Source(sources[i].source, sources[i].staticPrice, sources[i].sourceType, 0));
  //   }
  // }

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

  function getFallback() external view override returns (address) {
    return _fallback;
  }

  function setFallback(address fallback_) public override onlyOracleAdmin {
    _fallback = fallback_;
  }
}
