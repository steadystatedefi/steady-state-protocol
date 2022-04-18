// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Balances {
  struct RateAcc {
    uint128 accum;
    uint96 rate;
    uint32 updatedAt;
  }

  function sync(RateAcc memory b, uint32 at) internal pure returns (RateAcc memory) {
    uint256 adjustment = at - b.updatedAt;
    if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
      adjustment += b.accum;
      require(adjustment == (b.accum = uint128(adjustment)));
    }
    b.updatedAt = at;
    return b;
  }

  // function syncStorage(RateAcc storage b, uint32 at) internal {
  //   uint256 adjustment = at - b.updatedAt;
  //   if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
  //     adjustment += b.accum;
  //     require(adjustment == (b.accum = uint128(adjustment)));
  //   }
  //   b.updatedAt = at;
  // }

  // function setRateStorage(
  //   RateAcc storage b,
  //   uint32 at,
  //   uint256 rate
  // ) internal {
  //   syncStorage(b, at);
  //   require(rate == (b.rate = uint96(rate)));
  // }

  // function setRate(
  //   RateAcc memory b,
  //   uint32 at,
  //   uint256 rate
  // ) internal pure returns (RateAcc memory) {
  //   b = sync(b, at);
  //   require(rate == (b.rate = uint96(rate)));
  //   return b;
  // }

  function setRateAfterSync(RateAcc memory b, uint256 rate) internal view returns (RateAcc memory) {
    require(b.updatedAt == block.timestamp);
    require(rate == (b.rate = uint96(rate)));
    return b;
  }

  // function incRate(
  //   RateAcc memory b,
  //   uint32 at,
  //   uint256 rateIncrement
  // ) internal pure returns (RateAcc memory) {
  //   return setRate(b, at, b.rate + rateIncrement);
  // }

  // function decRate(
  //   RateAcc memory b,
  //   uint32 at,
  //   uint256 rateDecrement
  // ) internal pure returns (RateAcc memory) {
  //   return setRate(b, at, b.rate - rateDecrement);
  // }

  // struct RateAccWithUint8 {
  //   uint120 accum;
  //   uint96 rate;
  //   uint32 updatedAt;
  //   uint8 extra;
  // }

  // function sync(RateAccWithUint8 memory b, uint32 at) internal pure returns (RateAccWithUint8 memory) {
  //   uint256 adjustment = at - b.updatedAt;
  //   if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
  //     adjustment += b.accum;
  //     require(adjustment == (b.accum = uint120(adjustment)));
  //   }
  //   b.updatedAt = at;
  //   return b;
  // }

  // function syncStorage(RateAccWithUint8 storage b, uint32 at) internal {
  //   uint256 adjustment = at - b.updatedAt;
  //   if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
  //     adjustment += b.accum;
  //     require(adjustment == (b.accum = uint120(adjustment)));
  //   }
  //   b.updatedAt = at;
  // }

  // function setRateStorage(
  //   RateAccWithUint8 storage b,
  //   uint32 at,
  //   uint256 rate
  // ) internal {
  //   syncStorage(b, at);
  //   require(rate == (b.rate = uint96(rate)));
  // }

  // function setRate(
  //   RateAccWithUint8 memory b,
  //   uint32 at,
  //   uint256 rate
  // ) internal pure returns (RateAccWithUint8 memory) {
  //   b = sync(b, at);
  //   require(rate == (b.rate = uint96(rate)));
  //   return b;
  // }

  // function incRate(
  //   RateAccWithUint8 memory b,
  //   uint32 at,
  //   uint256 rateIncrement
  // ) internal pure returns (RateAccWithUint8 memory) {
  //   return setRate(b, at, b.rate + rateIncrement);
  // }

  // function decRate(
  //   RateAccWithUint8 memory b,
  //   uint32 at,
  //   uint256 rateDecrement
  // ) internal pure returns (RateAccWithUint8 memory) {
  //   return setRate(b, at, b.rate - rateDecrement);
  // }

  struct RateAccWithUint16 {
    uint120 accum;
    uint88 rate;
    uint32 updatedAt;
    uint16 extra;
  }

  function sync(RateAccWithUint16 memory b, uint32 at) internal pure returns (RateAccWithUint16 memory) {
    uint256 adjustment = at - b.updatedAt;
    if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
      adjustment += b.accum;
      require(adjustment == (b.accum = uint120(adjustment)));
    }
    b.updatedAt = at;
    return b;
  }

  // function syncStorage(RateAccWithUint16 storage b, uint32 at) internal {
  //   uint256 adjustment = at - b.updatedAt;
  //   if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
  //     adjustment += b.accum;
  //     require(adjustment == (b.accum = uint120(adjustment)));
  //   }
  //   b.updatedAt = at;
  // }

  // function setRateStorage(
  //   RateAccWithUint16 storage b,
  //   uint32 at,
  //   uint256 rate
  // ) internal {
  //   syncStorage(b, at);
  //   require(rate == (b.rate = uint88(rate)));
  // }

  // function setRate(
  //   RateAccWithUint16 memory b,
  //   uint32 at,
  //   uint256 rate
  // ) internal pure returns (RateAccWithUint16 memory) {
  //   b = sync(b, at);
  //   require(rate == (b.rate = uint88(rate)));
  //   return b;
  // }

  // function incRate(
  //   RateAccWithUint16 memory b,
  //   uint32 at,
  //   uint256 rateIncrement
  // ) internal pure returns (RateAccWithUint16 memory) {
  //   return setRate(b, at, b.rate + rateIncrement);
  // }

  // function decRate(
  //   RateAccWithUint16 memory b,
  //   uint32 at,
  //   uint256 rateDecrement
  // ) internal pure returns (RateAccWithUint16 memory) {
  //   return setRate(b, at, b.rate - rateDecrement);
  // }

  // struct RateAccWithUint32 {
  //   uint112 accum;
  //   uint80 rate;
  //   uint32 updatedAt;
  //   uint32 extra;
  // }

  // function sync(RateAccWithUint32 memory b, uint32 at) internal pure returns (RateAccWithUint32 memory) {
  //   uint256 adjustment = at - b.updatedAt;
  //   if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
  //     adjustment += b.accum;
  //     require(adjustment == (b.accum = uint112(adjustment)));
  //   }
  //   b.updatedAt = at;
  //   return b;
  // }

  // function syncStorage(RateAccWithUint32 storage b, uint32 at) internal {
  //   uint256 adjustment = at - b.updatedAt;
  //   if (adjustment > 0 && (adjustment = adjustment * b.rate) > 0) {
  //     adjustment += b.accum;
  //     require(adjustment == (b.accum = uint112(adjustment)));
  //   }
  //   b.updatedAt = at;
  // }

  // function setRateStorage(
  //   RateAccWithUint32 storage b,
  //   uint32 at,
  //   uint256 rate
  // ) internal {
  //   syncStorage(b, at);
  //   require(rate == (b.rate = uint80(rate)));
  // }

  // function setRate(
  //   RateAccWithUint32 memory b,
  //   uint32 at,
  //   uint256 rate
  // ) internal pure returns (RateAccWithUint32 memory) {
  //   b = sync(b, at);
  //   require(rate == (b.rate = uint80(rate)));
  //   return b;
  // }

  // function incRate(
  //   RateAccWithUint32 memory b,
  //   uint32 at,
  //   uint256 rateIncrement
  // ) internal pure returns (RateAccWithUint32 memory) {
  //   return setRate(b, at, b.rate + rateIncrement);
  // }

  // function decRate(
  //   RateAccWithUint32 memory b,
  //   uint32 at,
  //   uint256 rateDecrement
  // ) internal pure returns (RateAccWithUint32 memory) {
  //   return setRate(b, at, b.rate - rateDecrement);
  // }
}
