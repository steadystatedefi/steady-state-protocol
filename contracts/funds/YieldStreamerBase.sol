// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/ICollateralBorrowManager.sol';
import '../access/AccessHelper.sol';

import '../access/AccessHelper.sol';
import './interfaces/ICollateralFund.sol';
import './Collateralized.sol';

abstract contract YieldStreamerBase is Collateralized {
  using SafeERC20 for IERC20;
  using Math for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  uint32 private _rateCutOffAt;
  uint96 private _yieldRate;
  uint256 private _yieldDebt;

  struct YieldSource {
    uint8 sourceType;
    uint96 expectedRate;
    uint32 appliedSince;
  }

  mapping(address => YieldSource) private _sources;

  function internalCalcRateIntegral(uint32 from, uint32 till) internal view virtual returns (uint256 v) {
    (v, ) = _getRateIntegral(from, till);
  }

  function internalGetRateIntegral(uint32 from, uint32 till) internal virtual returns (uint256) {
    (uint256 v, uint256 yieldDebt) = _getRateIntegral(from, till);
    if (v != 0) {
      _yieldDebt = yieldDebt;
    }
    return v;
  }

  function _getRateIntegral(uint32 from, uint32 till) private view returns (uint256 v, uint256 yieldDebt) {
    uint32 cutOff = _rateCutOffAt;
    if (cutOff < till) {
      if (from >= cutOff) {
        return (0, 0);
      }
      till = cutOff;
    }

    v = _yieldRate * (till - from);
    yieldDebt = _yieldDebt;
    if (yieldDebt > 0) {
      (v, yieldDebt) = v.boundedSub2(yieldDebt);
    }
  }

  function internalAddYieldExcess(uint256) internal virtual;

  function internalAddYieldPayout(
    address source,
    uint256 amount,
    uint256 expectedRate
  ) internal {
    YieldSource storage s = _sources[source];
    State.require(s.sourceType != 0);

    uint32 at = uint32(block.timestamp);
    uint256 expectedAmount = uint256(at - s.appliedSince) * s.expectedRate;
    s.appliedSince = at;

    if (expectedAmount > amount) {
      _yieldDebt += expectedAmount - amount;
    } else if (expectedAmount < amount) {
      internalAddYieldExcess(amount - expectedAmount);
    }

    uint256 lastRate = s.expectedRate;
    if (lastRate != expectedRate) {
      _yieldRate = uint256(_yieldRate).addDelta(expectedRate, lastRate).asUint96();
    }
  }

  function internalAddYieldSource(address source, uint8 sourceType) internal {
    Value.require(sourceType != 0);
    Value.require(source != address(0));

    YieldSource storage s = _sources[source];
    State.require(s.sourceType == 0);
    s.sourceType = sourceType;
  }

  function internalRemoveYieldSource(address source) internal returns (bool ok) {
    if (ok = (_sources[source].sourceType != 0)) {
      internalAddYieldPayout(source, 0, 0);
    }
    delete _sources[source];
  }

  function internalGetYieldSource(address source)
    internal
    returns (
      uint8 sourceType,
      uint96 expectedRate,
      uint32 since
    )
  {
    YieldSource storage s = _sources[source];
    if ((sourceType = s.sourceType) != 0) {
      (expectedRate, since) = (s.expectedRate, s.appliedSince);
    }
    delete _sources[source];
  }
}
