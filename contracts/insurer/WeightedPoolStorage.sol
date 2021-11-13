// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IJoinHandler.sol';
import './InsurerPoolBase.sol';
import './WeightedRoundsBase.sol';

abstract contract WeightedPoolStorage is WeightedRoundsBase, InsurerPoolBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  WeightedPoolParams internal _params;

  struct UserBalance {
    uint128 premiumBase;
    uint128 balance; // scaled
  }
  mapping(address => UserBalance) internal _balances;
  mapping(address => uint256) internal _premiums;

  Balances.RateAcc internal _totalRate;

  struct OpenBalance {
    uint128 excessCoverage;
    uint112 buyOffCoverage;
    uint16 buyOffShare;
  }
  OpenBalance internal _openBalance;
  uint256 internal _buyOffBalance;

  address internal _joinHandler;

  function charteredDemand() public pure virtual returns (bool) {
    return true;
  }

  modifier onlyActiveInsured() {
    require(internalGetInsuredStatus(msg.sender) == InsuredStatus.Accepted);
    _;
  }

  modifier onlyInsured() {
    require(internalGetInsuredStatus(msg.sender) > InsuredStatus.Unknown);
    _;
  }

  function internalBatchAppend(
    uint64,
    uint32 openRounds,
    uint64 unitCount
  ) internal view override returns (uint24) {
    WeightedPoolParams memory params = _params;
    uint256 min = params.minAdvanceUnits / params.maxUnitsPerRound;
    uint256 max = params.maxAdvanceUnits / params.maxUnitsPerRound;
    if (min > type(uint24).max) {
      min = type(uint24).max;
      if (openRounds + min > max) {
        return 0;
      }
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

  function internalRoundLimits(
    uint64 totalUnitsBeforeBatch,
    uint24 batchRounds,
    uint16 unitPerRound,
    uint64 demandedUnits,
    uint16 maxShare
  )
    internal
    view
    override
    returns (
      uint16 maxAddUnitsPerRound,
      uint16, // minUnitsPerRound,
      uint16 // maxUnitsPerRound
    )
  {
    require(maxShare > 0);
    WeightedPoolParams memory params = _params;

    console.log('internalRoundLimits-0', totalUnitsBeforeBatch, demandedUnits, batchRounds);
    console.log('internalRoundLimits-1', unitPerRound, params.minUnitsPerRound, maxShare);

    uint256 x = (totalUnitsBeforeBatch +
      uint256(unitPerRound < params.minUnitsPerRound ? params.minUnitsPerRound : unitPerRound) *
      batchRounds).percentMul(maxShare);

    if (x > demandedUnits) {
      x = (x - demandedUnits + (batchRounds >> 1)) / batchRounds;
      maxAddUnitsPerRound = x >= type(uint16).max ? type(uint16).max : uint16(x);
    }

    x = maxAddUnitsPerRound + unitPerRound;
    if (params.maxUnitsPerRound >= x) {
      x = params.maxUnitsPerRound;
    } else if (x > type(uint16).max) {
      x = type(uint16).max;
    }

    console.log('internalRoundLimits-3', maxAddUnitsPerRound, x);
    return (maxAddUnitsPerRound, params.minUnitsPerRound, uint16(x));
  }

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

  function internalIsInvestor(address account) internal view virtual returns (bool) {
    UserBalance memory b = _balances[account];
    return b.premiumBase != 0 || b.balance != 0;
  }

  function internalGetStatus(address account) internal view virtual returns (InsuredStatus) {
    return super.internalGetInsuredStatus(account);
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
}
