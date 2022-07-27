// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/ICollateralStakeManager.sol';
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
  uint128 private _yieldDebt;

  uint16 private _pullableCount;
  uint16 private _nextPullable;
  mapping(uint256 => PullableSource) private _pullableSources;
  mapping(address => YieldSource) private _sources;

  struct YieldSource {
    uint16 pullableIndex;
    uint32 appliedSince;
    uint96 expectedRate;
  }

  struct PullableSource {
    YieldSourceType sourceType;
    address source;
  }

  function internalCalcRateIntegral(uint32 from, uint32 till) internal view virtual returns (uint256 v) {
    (v, ) = _getRateIntegral(from, till);
  }

  function internalGetRateIntegral(uint32 from, uint32 till) internal virtual returns (uint256) {
    (uint256 v, uint256 yieldDebt) = _getRateIntegral(from, till);
    if (v != 0) {
      _yieldDebt = uint128(yieldDebt);
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
    State.require(s.appliedSince != 0);

    uint32 at = uint32(block.timestamp);
    uint256 expectedAmount = uint256(at - s.appliedSince) * s.expectedRate;
    s.appliedSince = at;

    if (expectedAmount > amount) {
      _yieldDebt += (expectedAmount - amount).asUint128();
    } else if (expectedAmount < amount) {
      internalAddYieldExcess(amount - expectedAmount);
    }

    uint256 lastRate = s.expectedRate;
    if (lastRate != expectedRate) {
      _yieldRate = uint256(_yieldRate).addDelta(expectedRate, lastRate).asUint96();
    }
  }

  function isSourcePullable(YieldSourceType) private returns (bool) {}

  function internalAddYieldSource(address source, YieldSourceType sourceType) internal {
    Value.require(uint8(sourceType) != 0);
    Value.require(source != address(0));

    YieldSource storage s = _sources[source];
    State.require(s.appliedSince == 0);
    s.appliedSince = uint32(block.timestamp);

    if (sourceType > YieldSourceType.Passive) {
      PullableSource storage ps = _pullableSources[s.pullableIndex = ++_pullableCount];
      ps.source = source;
      ps.sourceType = sourceType;
    }
  }

  function internalRemoveYieldSource(address source) internal returns (bool ok) {
    YieldSource storage s = _sources[source];
    if (ok = (s.appliedSince != 0)) {
      internalAddYieldPayout(source, 0, 0);
      uint16 pullableIndex = s.pullableIndex;
      if (pullableIndex > 0) {
        uint16 index = _pullableCount--;
        if (pullableIndex != index) {
          State.require(pullableIndex < index);
          _sources[(_pullableSources[pullableIndex] = _pullableSources[index]).source].pullableIndex = pullableIndex;
        }
      }
    }
    delete _sources[source];
  }

  function internalIsYieldSource(address source) internal view returns (bool) {
    return _sources[source].appliedSince != 0;
  }

  function internalGetYieldSource(address source)
    internal
    view
    returns (
      YieldSourceType sourceType,
      uint96 expectedRate,
      uint32 since
    )
  {
    YieldSource storage s = _sources[source];
    if (s.appliedSince != 0) {
      (expectedRate, since) = (s.expectedRate, s.appliedSince);
      uint16 index = s.pullableIndex;
      sourceType = index == 0 ? YieldSourceType.Passive : _pullableSources[index].sourceType;
    }
  }

  function internalPullYield(uint256 availableYield, uint256 requestedYield) internal virtual returns (bool foundMore) {
    uint256 count = _pullableCount;
    if (count == 0) {
      return false;
    }

    uint256 last = _nextPullable;
    if (last != 0) {
      last--;
    }

    for (uint256 i = last + 1; i != last; i++) {
      if (i > count) {
        i = 0;
        continue;
      }
      PullableSource storage ps = _pullableSources[i];
      uint256 collectedYield = _pullYield(ps.sourceType, ps.source);
      if (collectedYield > 0) {
        foundMore = true;
      }

      if ((availableYield += collectedYield) >= requestedYield) {
        break;
      }
    }
    _nextPullable = uint16(last);
  }

  function _pullYield(YieldSourceType sourceType, address source) internal returns (uint256) {}
}

enum YieldSourceType {
  None,
  Passive
}
