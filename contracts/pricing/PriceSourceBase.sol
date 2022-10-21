// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';

/// @dev A template to work with encoded information about price sources.
abstract contract PriceSourceBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  // Encoding of source info uses overlapping fields in the structs, hence it is encoded manually
  /* 
  struct Source {
    uint4 sourceType; // source type
    uint6 decimals; // with offset of 18, i.e. 0 => 18, 1 => 19, 2 => 20 ... 45 => 63, 46 => 0, 47=> 1 ... 63 = 17
    uint6 internalFlags;
    uint8 maxValidity; // minutes

    union {
      [sourceType == 0]: struct {
        uint32 updatedAt;
        uint200 staticValue;
      }

      [otherwise]: struct {
        address source;
        uint8 callFlags;

        uint8 tolerance;
        uint56 target;
      }
    }     
  } 
  */

  uint8 private constant SOURCE_TYPE_OFS = 0;
  uint8 private constant SOURCE_TYPE_BIT = 4;
  uint256 private constant SOURCE_TYPE_MASK = (2**SOURCE_TYPE_BIT) - 1;

  uint8 private constant DECIMALS_OFS = SOURCE_TYPE_OFS + SOURCE_TYPE_BIT;
  uint8 private constant DECIMALS_BIT = 6;
  uint256 private constant DECIMALS_MASK = (2**DECIMALS_BIT) - 1;

  uint8 private constant FLAGS_OFS = DECIMALS_OFS + DECIMALS_BIT;
  uint8 private constant FLAGS_BIT = 6;
  uint256 private constant FLAGS_MASK = (2**FLAGS_BIT) - 1;

  uint256 private constant FLAG_CROSS_PRICED = 1 << (FLAGS_OFS + FLAGS_BIT - 1);
  uint8 internal constant EF_LIMIT_BREACHED = uint8(FLAG_CROSS_PRICED >> FLAGS_OFS);
  uint8 private constant CUSTOM_FLAG_MASK = EF_LIMIT_BREACHED - 1;

  uint8 private constant VALIDITY_OFS = FLAGS_OFS + FLAGS_BIT;
  uint8 private constant VALIDITY_BIT = 8;
  uint256 private constant VALIDITY_MASK = (2**VALIDITY_BIT) - 1;

  uint8 private constant PAYLOAD_OFS = VALIDITY_OFS + VALIDITY_BIT;

  uint8 private constant FEED_POST_PAYLOAD_OFS = PAYLOAD_OFS + 160 + 8;
  uint256 private constant FEED_PAYLOAD_CONFIG_AND_SOURCE_TYPE_MASK = (uint256(1) << FEED_POST_PAYLOAD_OFS) - 1;

  uint256 private constant MAX_STATIC_VALUE = (type(uint256).max << (PAYLOAD_OFS + 32)) >> (PAYLOAD_OFS + 32);

  uint256 private constant CONFIG_AND_SOURCE_TYPE_MASK = (uint256(1) << PAYLOAD_OFS) - 1;
  uint256 private constant CONFIG_MASK = CONFIG_AND_SOURCE_TYPE_MASK & ~SOURCE_TYPE_MASK;
  uint256 private constant INVERSE_CONFIG_MASK = ~CONFIG_MASK;

  struct CallHandler {
    function(uint8, address, address) internal view returns (uint256, uint32) handler;
  }

  mapping(address => uint256) private _encodedSources;
  mapping(address => address) private _crossTokens;

  function internalReadSource(address token) internal view returns (uint256, uint8) {
    return _readSource(token, true);
  }

  function _readSource(address token, bool notNested) private view returns (uint256, uint8 resultFlags) {
    uint256 encoded = _encodedSources[token];
    if (encoded == 0) {
      return (0, 0);
    }

    uint8 callType = uint8(encoded & SOURCE_TYPE_MASK);

    (uint256 v, uint32 t) = callType != 0 ? _callSource(callType, encoded, token) : _callStatic(encoded);

    uint8 maxValidity = uint8(encoded >> VALIDITY_OFS);
    if (!(maxValidity == 0 || t == 0 || t + maxValidity * 1 minutes >= block.timestamp)) {
      revert Errors.PriceExpired(token);
    }

    resultFlags = uint8((encoded >> FLAGS_OFS) & FLAGS_MASK);
    uint8 decimals = uint8(((encoded >> DECIMALS_OFS) + 18) & DECIMALS_MASK);

    if (encoded & FLAG_CROSS_PRICED != 0) {
      State.require(notNested);
      uint256 vc;
      (vc, ) = _readSource(_crossTokens[token], false);
      v *= vc;
      decimals += 18;
    }

    if (decimals > 18) {
      v = v.divUp(10**uint8(decimals - 18));
    } else {
      v *= 10**uint8(18 - decimals);
    }

    if (callType != 0 && _checkLimits(v, encoded)) {
      resultFlags |= EF_LIMIT_BREACHED;
    }

    return (v, resultFlags);
  }

  uint256 private constant TARGET_UNIT = 10**9;
  uint256 private constant TOLERANCE_ONE = 800;

  function _callSource(
    uint8 callType,
    uint256 encoded,
    address token
  ) private view returns (uint256 v, uint32 t) {
    return internalGetHandler(callType)(uint8(encoded >> (PAYLOAD_OFS + 160)), address(uint160(encoded >> PAYLOAD_OFS)), token);
  }

  function _checkLimits(uint256 v, uint256 encoded) private pure returns (bool) {
    encoded >>= FEED_POST_PAYLOAD_OFS;
    uint8 tolerance = uint8(encoded);
    uint256 target = encoded >> 8;
    target *= TARGET_UNIT;

    v = v > target ? v - target : target - v;
    return (v * TOLERANCE_ONE > target * tolerance);
  }

  function _callStatic(uint256 encoded) private pure returns (uint256 v, uint32 t) {
    encoded >>= PAYLOAD_OFS;
    return (encoded >> 32, uint32(encoded));
  }

  function internalGetHandler(uint8 callType)
    internal
    view
    virtual
    returns (function(uint8, address, address) internal view returns (uint256, uint32));

  function internalSetStatic(
    address token,
    uint256 value,
    uint32 since
  ) internal {
    uint256 encoded = _encodedSources[token];
    Value.require(value <= MAX_STATIC_VALUE);

    if (value == 0) {
      since = 0;
    } else if (since == 0) {
      since = uint32(block.timestamp);
    }

    value = (value << 32) | since;
    _encodedSources[token] = (value << PAYLOAD_OFS) | (encoded & CONFIG_MASK);
  }

  function internalUnsetSource(address token) internal {
    delete _encodedSources[token];
  }

  function internalSetCustomFlags(
    address token,
    uint8 unsetFlags,
    uint8 setFlags
  ) internal {
    Value.require((unsetFlags | setFlags) <= CUSTOM_FLAG_MASK);

    uint256 encoded = _encodedSources[token];

    if (unsetFlags != 0) {
      encoded &= ~(uint256(unsetFlags) << FLAGS_OFS);
    }
    encoded |= uint256(setFlags) << FLAGS_OFS;

    _encodedSources[token] = encoded;
  }

  function internalSetSource(
    address token,
    uint8 callType,
    address feed,
    uint8 callFlags
  ) internal {
    Value.require(feed != address(0));
    Value.require(callType > 0 && callType <= SOURCE_TYPE_MASK);

    internalGetHandler(callType);

    uint256 encoded = _encodedSources[token] & CONFIG_MASK;
    encoded |= callType | (((uint256(callFlags) << 160) | uint160(feed)) << PAYLOAD_OFS);

    _encodedSources[token] = encoded;
  }

  function internalSetPriceTolerance(
    address token,
    uint256 targetPrice,
    uint16 tolerancePct
  ) internal {
    uint256 encoded = _encodedSources[token];
    State.require(encoded & SOURCE_TYPE_MASK != 0);

    uint256 v;
    if (targetPrice != 0) {
      v = uint256(tolerancePct).percentMul(TOLERANCE_ONE);
      Value.require(v <= type(uint8).max);

      targetPrice = targetPrice.divUp(TARGET_UNIT);
      Value.require(targetPrice > 0);
      v |= targetPrice << 8;

      v <<= FEED_POST_PAYLOAD_OFS;
    }

    _encodedSources[token] = v | (encoded & FEED_PAYLOAD_CONFIG_AND_SOURCE_TYPE_MASK);
  }

  function _ensureCrossPriceToken(address crossPrice) private view {
    uint256 encoded = _encodedSources[crossPrice];

    Value.require(encoded != 0);
    State.require(encoded & FLAG_CROSS_PRICED == 0);
    State.require(_crossTokens[crossPrice] == crossPrice);
  }

  function internalSetConfig(
    address token,
    uint8 decimals,
    address crossPrice,
    uint32 maxValidity
  ) internal {
    uint256 encoded = _encodedSources[token];
    State.require(encoded != 0);

    Value.require(decimals <= DECIMALS_MASK);
    decimals = uint8(((DECIMALS_MASK - 17) + decimals) & DECIMALS_MASK);

    maxValidity = maxValidity == type(uint32).max ? 0 : (maxValidity + 1 minutes - 1) / 1 minutes;
    Value.require(maxValidity <= type(uint8).max);

    if (crossPrice != address(0) && crossPrice != token) {
      _ensureCrossPriceToken(crossPrice);
      encoded |= FLAG_CROSS_PRICED;
    } else {
      encoded &= ~FLAG_CROSS_PRICED;
    }

    encoded &= ~(VALIDITY_MASK << VALIDITY_OFS) | (DECIMALS_MASK << DECIMALS_OFS);
    _encodedSources[token] = encoded | (uint256(maxValidity) << VALIDITY_OFS) | (uint256(decimals) << DECIMALS_OFS);
    _crossTokens[token] = crossPrice;
  }

  function internalGetConfig(address token)
    internal
    view
    returns (
      bool ok,
      uint8 decimals,
      address crossPrice,
      uint32 maxValidity,
      uint8 flags,
      bool staticPrice
    )
  {
    uint256 encoded = _encodedSources[token];
    if (encoded != 0) {
      ok = true;
      staticPrice = encoded & SOURCE_TYPE_MASK == 0;

      decimals = uint8(((encoded >> DECIMALS_OFS) + 18) & DECIMALS_MASK);
      maxValidity = uint8(encoded >> VALIDITY_OFS);

      if (encoded & FLAG_CROSS_PRICED != 0) {
        crossPrice = _crossTokens[token];
      }

      flags = uint8((encoded >> FLAGS_OFS) & CUSTOM_FLAG_MASK);
    }
  }

  function internalGetSource(address token)
    internal
    view
    returns (
      uint8 callType,
      address feed,
      uint8 callFlags,
      uint256 target,
      uint16 tolerance
    )
  {
    uint256 encoded = _encodedSources[token];
    if (encoded != 0) {
      State.require((callType = uint8(encoded & SOURCE_TYPE_MASK)) != 0);
      encoded >>= PAYLOAD_OFS;

      feed = address(uint160(encoded));
      encoded >>= 160;
      callFlags = uint8(encoded);
      encoded >>= 8;

      tolerance = uint16(uint256(uint8(encoded)).percentDiv(TOLERANCE_ONE));
      target = (encoded >> 8) * TARGET_UNIT;
    }
  }

  function internalGetStatic(address token) internal view returns (uint256, uint32) {
    uint256 encoded = _encodedSources[token];
    State.require(encoded & SOURCE_TYPE_MASK == 0);
    encoded >>= PAYLOAD_OFS;

    return (encoded >> 32, uint32(encoded));
  }
}
