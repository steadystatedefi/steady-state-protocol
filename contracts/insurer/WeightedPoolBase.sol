// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import './InsurerPoolBase.sol';
import './WeightedRoundsBase.sol';

abstract contract WeightedPoolBase is WeightedRoundsBase, InsurerPoolBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  uint256 private _excessCoverage;

  uint64 private _maxAdvanceUnits = 1000;
  uint16 private _minInsuredShare = 100; // 1%

  struct UserBalance {
    uint128 balance; // scaled
    uint128 premiumBase;
  }
  mapping(address => UserBalance) private _balances;
  mapping(address => uint256) private _premiums;

  Balances.RateAcc private _totalRate;

  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  function charteredDemand() public pure override returns (bool) {
    return true;
  }

  function onCoverageDeclined(address insured) external override {
    insured;
    Errors.notImplemented();
  }

  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external override returns (uint256 addedCount) {}

  function cancelCoverageDemand(uint256 unitCount, bool hasMore) external override returns (uint256 cancelledUnits) {
    unitCount;
    hasMore;
    Errors.notImplemented();
    return 0;
  }

  function getCoverageDemand(address insured)
    external
    view
    override
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  function receiveDemandedCoverage(address insured)
    external
    override
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    coverage = internalUpdateCoveredDemand(params);

    // TODO transfer coverage?

    return (params.receivedCoverage, coverage);
  }

  function _roundMinMax() private pure returns (uint16 minUnitsPerRound, uint16 maxUnitsPerRound) {
    minUnitsPerRound = 1; // TODO should depend on a number of insured pools with "hasMore" status
    maxUnitsPerRound = 10; // TODO should depend of minUnitsPerRound and pool growth rate
  }

  function internalRoundLimits(
    uint64 totalUnitsBeforeBatch,
    uint24 batchRounds,
    uint64 demandedUnits,
    uint16 maxShare
  )
    internal
    view
    override
    returns (
      uint16 maxAddUnitsPerRound,
      uint16 minUnitsPerRound,
      uint16 maxUnitsPerRound
    )
  {
    uint16 minShare = _minInsuredShare;

    uint256 units = (PercentageMath.ONE + (minShare >> 1)) / minShare;
    if (totalUnitsBeforeBatch > units) {
      units = totalUnitsBeforeBatch;
    }

    (minUnitsPerRound, maxUnitsPerRound) = _roundMinMax();

    uint256 x = (units + uint256(minUnitsPerRound) * batchRounds).percentMul(maxShare < minShare ? minShare : maxShare);

    if (x > demandedUnits) {
      x -= demandedUnits;
      maxAddUnitsPerRound = x >= type(uint16).max ? type(uint16).max : uint16(x);
    }
  }

  function internalBatchSplit(
    uint64 totalDemandedUnits,
    uint64 demandedUnits,
    uint64 minUnits,
    uint24 batchRounds,
    uint24 remainingUnits
  ) internal view override returns (uint24 splitRounds) {
    if (batchRounds > 0) {
      if (demandedUnits >= minUnits || demandedUnits + remainingUnits < minUnits) {
        if (remainingUnits <= batchRounds >> 2) {
          return 0;
        }
      }
      return remainingUnits;
    }

    demandedUnits = _maxAdvanceUnits;
    if (totalDemandedUnits >= demandedUnits) {
      return 0;
    }
    (, uint16 maxUnitsPerRound) = _roundMinMax();
    totalDemandedUnits = (totalDemandedUnits - demandedUnits) / maxUnitsPerRound;

    return totalDemandedUnits > type(uint24).max ? type(uint24).max : uint24(totalDemandedUnits);
  }

  function internalHandleInvestment(
    address investor,
    uint256 amount,
    bytes memory data
  ) internal override {
    if (data.length > 0) {
      abi.decode(data, ());
    }
    internalMintForCoverage(investor, amount);
  }

  function _beforeBalanceUpdate(address account)
    private
    returns (UserBalance memory b, Balances.RateAcc memory totals)
  {
    totals = _totalRate.sync(uint32(block.timestamp));
    b = _balances[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        _premiums[account] += b.balance * premiumDiff;
      }
    }
  }

  function _afterBalanceUpdate(uint256 newExcess, Balances.RateAcc memory totals)
    private
    returns (Balances.RateAcc memory)
  {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    uint256 rate = coverage.premiumRate.rayMul(exchangeRate());
    if (newExcess > 0) {
      uint256 covered = coverage.totalCovered + coverage.pendingCovered;
      rate = (rate * covered) / (newExcess + covered);
    }
    return _totalRate = totals.setRate(uint32(block.timestamp), rate);
  }

  function internalMintForCoverage(address account, uint256 coverageAmount) internal {
    require(coverageAmount > 0);

    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    uint256 excess = _excessCoverage;
    (uint256 newExcess, , AddCoverageParams memory params) = super.internalAddCoverage(
      coverageAmount + excess,
      type(uint256).max
    );
    if (newExcess != excess) {
      _excessCoverage = newExcess;
    }

    if (params.premiumRateUpdated || excess != 0 || newExcess != 0) {
      totals = _afterBalanceUpdate(newExcess, totals);
    }

    uint256 amount = coverageAmount.rayDiv(exchangeRate()) + b.balance;
    require(amount == (b.balance = uint128(amount)));
    b.premiumBase = totals.accum;
    _balances[account] = b;
  }

  function internalBurn(address account, uint256 amount) internal returns (uint256 coverageAmount) {
    require(amount > 0);

    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);
    if (amount == type(uint256).max) {
      (amount, b.balance) = (b.balance, 0);
    } else {
      b.balance = uint128(b.balance - amount);
    }

    coverageAmount = amount.rayMul(exchangeRate());
    _excessCoverage -= coverageAmount;
    totals = _afterBalanceUpdate(_excessCoverage, totals);

    b.premiumBase = totals.accum;
    _balances[account] = b;
    return coverageAmount;
  }

  function balanceOf(address account) external view override returns (uint256) {
    return uint256(_balances[account].balance).rayMul(exchangeRate());
  }

  function scaledBalanceOf(address account) external view returns (uint256) {
    return _balances[account].balance;
  }

  function totalSupply() external view override returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered;
  }

  function interestRate(address account) external view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = _totalRate.sync(uint32(block.timestamp));
    UserBalance memory b = _balances[account];

    accumulated = _premiums[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        accumulated += b.balance * premiumDiff;
      }
      return (b.balance * totals.rate, accumulated);
    }

    return (0, accumulated);
  }

  function exchangeRate() public pure override returns (uint256) {
    return WadRayMath.RAY;
  }
}
