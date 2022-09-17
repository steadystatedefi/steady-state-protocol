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
  uint16 private _lastPullable;
  mapping(uint256 => PullableSource) private _pullableSources;
  mapping(address => YieldSource) private _sources;

  struct YieldSource {
    uint16 pullableIndex;
    uint32 appliedSince;
    uint96 expectedRate;
  }

  struct PullableSource {
    uint8 sourceType;
    address source;
  }

  function internalGetYieldInfo()
    internal
    view
    returns (
      uint256 rate,
      uint256 debt,
      uint32 cutOff
    )
  {
    return (_yieldRate, _yieldDebt, _rateCutOffAt);
  }

  function internalCalcRateIntegral(uint32 from, uint32 till) internal view virtual returns (uint256 v) {
    v = _calcDiff(from, till);
    if (v > 0) {
      v = v.boundedSub(_yieldDebt);
    }
  }

  function internalGetRateIntegral(uint32 from, uint32 till) internal virtual returns (uint256 v) {
    v = _calcDiff(from, till);
    if (v > 0) {
      uint256 yieldDebt = _yieldDebt;
      if (yieldDebt > 0) {
        (v, yieldDebt) = v.boundedXSub(yieldDebt);
        _yieldDebt = uint128(yieldDebt);
      }
    }
  }

  function internalSetRateCutOff(uint32 at) internal {
    _rateCutOffAt = at;
  }

  function _calcDiff(uint32 from, uint32 till) private view returns (uint256) {
    uint32 cutOff = _rateCutOffAt;
    if (cutOff > 0) {
      if (from >= cutOff) {
        return 0;
      }
      if (till > cutOff) {
        till = cutOff;
      }
    }
    return till == from ? 0 : uint256(_yieldRate) * (till - from);
  }

  function internalAddYieldExcess(uint256) internal virtual;

  // NB! Total integral must be synced before calling this method
  function internalAddYieldPayout(
    address source,
    uint256 amount,
    uint256 expectedRate
  ) internal {
    YieldSource storage s = _sources[source];
    State.require(s.appliedSince != 0);

    uint32 at = uint32(block.timestamp);
    uint256 lastRate = s.expectedRate;

    uint256 expectedAmount = uint256(at - s.appliedSince) * lastRate + _yieldDebt;
    s.appliedSince = at;

    if (expectedAmount > amount) {
      _yieldDebt = (expectedAmount - amount).asUint128();
    } else {
      _yieldDebt = 0;
      if (expectedAmount < amount) {
        internalAddYieldExcess(amount - expectedAmount);
      }
    }

    if (lastRate != expectedRate) {
      s.expectedRate = expectedRate.asUint96();
      _yieldRate = (uint256(_yieldRate) + expectedRate - lastRate).asUint96();
    }
  }

  event YieldSourceAdded(address indexed source, uint8 sourceType);
  event YieldSourceRemoved(address indexed source);

  function internalAddYieldSource(address source, uint8 sourceType) internal {
    Value.require(source != address(0));
    Value.require(sourceType != uint8(YieldSourceType.None));

    YieldSource storage s = _sources[source];
    State.require(s.appliedSince == 0);
    s.appliedSince = uint32(block.timestamp);

    if (sourceType > uint8(YieldSourceType.Passive)) {
      PullableSource storage ps = _pullableSources[s.pullableIndex = ++_pullableCount];
      ps.source = source;
      ps.sourceType = sourceType;
    }
    emit YieldSourceAdded(source, sourceType);
  }

  // NB! Total integral must be synced before calling this method
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
      emit YieldSourceRemoved(source);
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
      uint8 sourceType,
      uint96 expectedRate,
      uint32 since
    )
  {
    YieldSource storage s = _sources[source];
    if ((since = s.appliedSince) != 0) {
      expectedRate = s.expectedRate;
      uint16 index = s.pullableIndex;
      sourceType = index == 0 ? uint8(YieldSourceType.Passive) : _pullableSources[index].sourceType;
    }
  }

  event YieldSourcePulled(address indexed source, uint256 amount);

  function internalPullYield(uint256 availableYield, uint256 requestedYield) internal virtual returns (bool foundMore) {
    uint256 count = _pullableCount;
    if (count == 0) {
      return false;
    }

    uint256 i = _lastPullable;
    if (i > count) {
      i = 0;
    }

    for (uint256 n = count; n > 0; n--) {
      i = 1 + (i % count);

      PullableSource storage ps = _pullableSources[i];
      uint256 collectedYield = internalPullYieldFrom(ps.sourceType, ps.source);

      if (collectedYield > 0) {
        emit YieldSourcePulled(ps.source, collectedYield);
        foundMore = true;
      }

      if ((availableYield += collectedYield) >= requestedYield) {
        break;
      }
    }
    _lastPullable = uint16(i);
  }

  function internalPullYieldFrom(uint8 sourceType, address source) internal virtual returns (uint256);
}

enum YieldSourceType {
  None,
  Passive
}
