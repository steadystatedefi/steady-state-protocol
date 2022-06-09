// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../insurance/InsurancePoolBase.sol';
import './WeightedRoundsBase.sol';

// Contains all variables for both base and extension contract. Allows for upgrades without corruption

/// @dev
/// @dev WARNING! This contract MUST NOT be extended with new fields after deployment
/// @dev
abstract contract WeightedPoolStorage is WeightedRoundsBase, InsurancePoolBase {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  WeightedPoolParams internal _params;

  struct UserBalance {
    uint128 balance; // scaled
    uint128 extra;
  }
  mapping(address => UserBalance) internal _balances;

  /// @dev Amount of coverage provided to the pool that is not satisfying demand
  uint256 internal _excessCoverage;
  event ExcessCoverageIncreased(uint256 coverageExcess);

  address internal _joinHandler;

  function _onlyActiveInsured() private view {
    require(internalGetInsuredStatus(msg.sender) == InsuredStatus.Accepted);
  }

  modifier onlyActiveInsured() {
    _onlyActiveInsured();
    _;
  }

  function _onlyInsured() private view {
    require(internalGetInsuredStatus(msg.sender) > InsuredStatus.Unknown);
  }

  modifier onlyInsured() {
    _onlyInsured();
    _;
  }

  ///@return The number of rounds to initialize a new batch
  function internalBatchAppend(
    uint80,
    uint32 openRounds,
    uint64 unitCount
  ) internal view override returns (uint24) {
    WeightedPoolParams memory params = _params;

    uint256 min = params.minAdvanceUnits / params.maxUnitsPerRound;
    uint256 max = params.maxAdvanceUnits / params.maxUnitsPerRound;
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
      uint16, // readyUnitsPerRound //TODO: These labels do not correspond with actual return values
      uint16 // maxUnitsPerRound
    )
  {
    WeightedPoolParams memory params = _params;

    // total # of units could be allocated when this round if full
    uint256 x = uint256(unitPerRound < params.minUnitsPerRound ? params.minUnitsPerRound : unitPerRound + 1) *
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
      if (unitPerRound + x >= params.maxUnitsPerRound) {
        if (unitPerRound < params.minUnitsPerRound) {
          // this prevents lockup of a batch when demand is added by small portions
          params.minUnitsPerRound = unitPerRound + 1;
        }
      }

      if (x > type(uint16).max) {
        x = type(uint16).max;
      }
    }

    return (uint16(x), params.minUnitsPerRound, params.maxUnitsPerRound, params.overUnitsPerRound);
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

  function internalGetStatus(address account) internal view virtual returns (InsuredStatus) {
    return super.internalGetInsuredStatus(account);
  }

  function internalIsInvestor(address account) internal view virtual returns (bool) {
    UserBalance memory b = _balances[account];
    return b.extra != 0 || b.balance != 0;
  }
}

interface IExcessHandler {
  function pushCoverageExcess() external;
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
  uint16 maxDrawdown;
}
