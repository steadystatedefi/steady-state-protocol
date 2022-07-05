// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IInsurerGovernor.sol';
import '../governance/GovernedHelper.sol';
import './WeightedRoundsBase.sol';

abstract contract WeightedPoolConfig is WeightedRoundsBase, GovernedHelper {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  WeightedPoolParams internal _params;
  uint256 private _loopLimits;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedRoundsBase(unitSize) GovernedHelper(acl, collateral_) {}

  function _onlyActiveInsured(address insurer) internal view {
    require(internalGetStatus(insurer) == InsuredStatus.Accepted);
  }

  function _onlyInsured(address insurer) private view {
    require(internalGetStatus(insurer) > InsuredStatus.Unknown);
  }

  modifier onlyActiveInsured() {
    _onlyActiveInsured(msg.sender);
    _;
  }

  modifier onlyInsured() {
    _onlyInsured(msg.sender);
    _;
  }

  function internalSetTypedGovernor(IInsurerGovernor addr) internal {
    _governorIsContract = true;
    _setGovernor(address(addr));
  }

  function internalSetGovernor(address addr) internal virtual {
    // will also return false for EOA
    _governorIsContract = ERC165Checker.supportsInterface(addr, type(IInsurerGovernor).interfaceId);
    _setGovernor(addr);
  }

  function governorContract() internal view virtual returns (IInsurerGovernor) {
    return IInsurerGovernor(_governorIsContract ? governorAccount() : address(0));
  }

  function internalGetStatus(address account) internal view virtual returns (InsuredStatus) {
    return internalGetInsuredStatus(account);
  }

  function internalDefaultLoopLimits(uint16[] memory limits) internal virtual {
    uint256 v;
    for (uint256 i = limits.length; i > 0; ) {
      i--;
      v = (v << 16) | uint16(limits[i]);
    }
    _loopLimits = v;
  }

  function internalSetPoolParams(WeightedPoolParams memory params) internal virtual {
    require(params.minUnitsPerRound > 0);
    require(params.maxUnitsPerRound >= params.minUnitsPerRound);
    require(params.overUnitsPerRound >= params.maxUnitsPerRound);

    require(params.maxAdvanceUnits >= params.minAdvanceUnits);
    require(params.minAdvanceUnits >= params.maxUnitsPerRound);

    require(params.minInsuredShare > 0);
    require(params.maxInsuredShare > params.minInsuredShare);
    require(params.maxInsuredShare <= PercentageMath.ONE);

    require(params.riskWeightTarget > 0);
    require(params.riskWeightTarget < PercentageMath.ONE);

    require(params.maxDrawdownInverse >= PercentageMath.HALF_ONE);
    _params = params;
  }

  ///@return The number of rounds to initialize a new batch
  function internalBatchAppend(
    uint80,
    uint32 openRounds,
    uint64 unitCount
  ) internal view override returns (uint24) {
    uint256 max = _params.maxUnitsPerRound;
    uint256 min = _params.minAdvanceUnits / max;
    max = _params.maxAdvanceUnits / max;

    if (min > type(uint24).max) {
      if (openRounds + min > max) {
        return 0;
      }
      min = type(uint24).max;
    }

    if (openRounds + min > max) {
      if (min < (max >> 1) || openRounds > (max >> 1)) {
        return 0;
      }
    }

    if (unitCount > type(uint24).max) {
      unitCount = type(uint24).max;
    }

    if ((unitCount /= uint64(min)) <= 1) {
      return uint24(min);
    }

    if ((max = (max - openRounds) / min) < unitCount) {
      min *= max;
    } else {
      min *= unitCount;
    }
    require(min > 0); // TODO sanity check - remove later

    return uint24(min);
  }

  function internalGetPassiveCoverageUnits() internal view returns (uint256) {}

  /// @dev Calculate the limits of the number of units that can be added to a round
  function internalRoundLimits(
    uint80 totalUnitsBeforeBatch,
    uint24 batchRounds,
    uint16 unitPerRound,
    uint64 demandedUnits,
    uint16 maxShare
  )
    internal
    view
    override
    returns (
      uint16, // maxShareUnitsPerRound,
      uint16, // minUnitsPerRound,
      uint16, // readyUnitsPerRound
      uint16 // maxUnitsPerRound
    )
  {
    (uint16 minUnitsPerRound, uint16 maxUnitsPerRound) = (_params.minUnitsPerRound, _params.maxUnitsPerRound);

    // total # of units could be allocated when this round if full
    uint256 x = uint256(unitPerRound < minUnitsPerRound ? minUnitsPerRound : unitPerRound + 1) *
      batchRounds +
      totalUnitsBeforeBatch +
      internalGetPassiveCoverageUnits();

    // max of units that can be added in total for the share not to be exceeded
    x = x.percentMul(maxShare);

    if (x < demandedUnits + batchRounds) {
      x = 0;
    } else {
      unchecked {
        x = (x - demandedUnits) / batchRounds;
      }
      if (unitPerRound + x >= maxUnitsPerRound) {
        if (unitPerRound < minUnitsPerRound) {
          // this prevents lockup of a batch when demand is added by small portions
          minUnitsPerRound = unitPerRound + 1;
        }
      }

      if (x > type(uint16).max) {
        x = type(uint16).max;
      }
    }

    return (uint16(x), minUnitsPerRound, maxUnitsPerRound, _params.overUnitsPerRound);
  }

  /// TODO
  function internalBatchSplit(
    uint64 demandedUnits,
    uint64 minUnits,
    uint24 batchRounds,
    uint24 remainingUnits
  ) internal pure override returns (uint24 splitRounds) {
    // console.log('internalBatchSplit-0', demandedUnits, minUnits);
    // console.log('internalBatchSplit-1', batchRounds, remainingUnits);
    if (demandedUnits >= minUnits || demandedUnits + remainingUnits < minUnits) {
      if (remainingUnits <= batchRounds >> 2) {
        return 0;
      }
    }
    return remainingUnits;
  }

  function defaultLoopLimit(LoopLimitType t, uint256 limit) internal view returns (uint256) {
    if (limit == 0) {
      limit = uint16(_loopLimits >> (uint8(t) << 1));
      if (limit == 0) {
        limit = t > LoopLimitType.ReceivableDemandedCoverage ? 31 : 255;
      }
    }
    return limit;
  }
}

struct WeightedPoolParams {
  uint32 maxAdvanceUnits;
  uint32 minAdvanceUnits;
  uint16 riskWeightTarget;
  uint16 minInsuredShare;
  uint16 maxInsuredShare;
  uint16 minUnitsPerRound;
  uint16 maxUnitsPerRound;
  uint16 overUnitsPerRound;
  uint16 maxDrawdownInverse; // 100% = no drawdown
}

enum LoopLimitType {
  // View
  ReceivableDemandedCoverage,
  // Modify
  AddCoverageDemand,
  CancelCoverageDemand,
  ReceiveDemandedCoverage
}
