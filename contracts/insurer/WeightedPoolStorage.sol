// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IJoinHandler.sol';
import '../insurance/InsurancePoolBase.sol';
import './WeightedRoundsBase.sol';

// Contains all variables for both base and extension contract. Allows for upgrades without corruption

/// @dev
/// @dev WARNING! This contract MUST NOT be extended with new fields after deployment
/// @dev
abstract contract WeightedPoolStorage is WeightedRoundsBase, InsurancePoolBase {
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

  Balances.RateAcc private _totalRate;

  uint256 internal _excessCoverage;
  uint256 internal _inverseExchangeRate;

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

  ///@dev Used to determine the number of rounds to initialize a new batch
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
    WeightedPoolParams memory params = _params;

    // max units that can be added in total for the share not to be exceeded
    uint256 x = (totalUnitsBeforeBatch +
      uint256(unitPerRound < params.minUnitsPerRound ? params.minUnitsPerRound : unitPerRound + 1) *
      batchRounds).percentMul(maxShare);

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

  function exchangeRate() public view virtual returns (uint256) {
    return WadRayMath.RAY - _inverseExchangeRate;
  }

  /// @dev Performed before balance updates. The total rate accum by the pool is updated, and then the user balance is updated
  function _beforeAnyBalanceUpdate() internal view returns (Balances.RateAcc memory totals) {
    totals = _totalRate.sync(uint32(block.timestamp));
  }

  /// @dev Performed before balance updates. The total rate accum by the pool is updated, and then the user balance is updated
  function _beforeBalanceUpdate(address account)
    internal
    returns (UserBalance memory b, Balances.RateAcc memory totals)
  {
    totals = _beforeAnyBalanceUpdate();
    b = _syncBalance(account, totals);
  }

  /// @dev Updates _premiums with total premium earned by user. Each user's balance is marked by the amount
  ///  of premium collected by the pool at time of update
  function _syncBalance(address account, Balances.RateAcc memory totals) internal returns (UserBalance memory b) {
    b = _balances[account];
    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        _premiums[account] += premiumDiff.rayMul(b.balance);
      }
    }
    b.premiumBase = totals.accum;
  }

  /// @dev After the balance of the pool is updated, update the _totalRate
  function _afterBalanceUpdate(
    uint256 newExcess,
    Balances.RateAcc memory totals,
    DemandedCoverage memory coverage
  ) internal returns (Balances.RateAcc memory) {
    // console.log('_afterBalanceUpdate', coverage.premiumRate, newExcess, coverage.totalCovered + coverage.pendingCovered);
    uint256 rate = coverage.premiumRate == 0
      ? 0
      : uint256(coverage.premiumRate).rayDiv(newExcess + coverage.totalCovered + coverage.pendingCovered); // earns per second * 10^27
    _totalRate = totals.setRateAfterSync(rate.rayMul(exchangeRate()));
    return totals;
  }
}

abstract contract WeightedPoolTokenStorage is WeightedPoolStorage, ERC20BalancelessBase {}

struct WeightedPoolParams {
  uint32 maxAdvanceUnits;
  uint32 minAdvanceUnits;
  uint16 riskWeightTarget;
  uint16 minInsuredShare;
  uint16 maxInsuredShare;
  uint16 minUnitsPerRound;
  uint16 maxUnitsPerRound;
  uint16 overUnitsPerRound;
}
