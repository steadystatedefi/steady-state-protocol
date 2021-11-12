// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import './InsurerPoolBase.sol';
import './WeightedRoundsBase.sol';

abstract contract WeightedPoolBase is WeightedRoundsBase, InsurerPoolBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  struct UserBalance {
    uint128 premiumBase;
    uint128 balance; // scaled
  }
  mapping(address => UserBalance) private _balances;
  mapping(address => uint256) private _premiums;

  Balances.RateAcc private _totalRate;

  uint256 private _excessCoverage;

  WeightedPoolParams private _params;

  function internalSetPoolParams(WeightedPoolParams memory params) internal {
    require(params.minUnitsPerRound > 0);
    require(params.maxUnitsPerRound >= params.minUnitsPerRound);

    require(params.maxAdvanceUnits >= params.minAdvanceUnits);
    require(params.minAdvanceUnits >= params.maxUnitsPerRound);

    require(params.minInsuredShare > 0);
    require(params.maxInsuredShare > params.minInsuredShare);
    require(params.maxInsuredShare <= PercentageMath.ONE);

    require(params.riskWeightTarget > 0);
    require(params.riskWeightTarget < PercentageMath.ONE);
    _params = params;
  }

  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  function charteredDemand() public pure override returns (bool) {
    return true;
  }

  function onCoverageDeclined(address insured) external override onlyCollateralFund {
    insured;
    Errors.notImplemented();
  }

  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external override onlyActiveInsured returns (uint256 addedCount) {
    // TODO access control
    AddCoverageDemandParams memory params;
    params.insured = msg.sender;
    require(premiumRate == (params.premiumRate = uint40(premiumRate)));
    params.loopLimit = ~params.loopLimit;
    hasMore;
    require(unitCount <= type(uint64).max);
    console.log('premiumRate', premiumRate);

    return unitCount - super.internalAddCoverageDemand(uint64(unitCount), params);
  }

  function cancelCoverageDemand(uint256 unitCount, bool hasMore)
    external
    override
    onlyActiveInsured
    returns (uint256 cancelledUnits)
  {
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
    onlyActiveInsured
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    coverage = internalUpdateCoveredDemand(params);

    // TODO transfer coverage?

    return (params.receivedCoverage, coverage);
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
        _premiums[account] += premiumDiff.rayMul(b.balance);
      }
    }
  }

  function _afterBalanceUpdate(uint256 newExcess, Balances.RateAcc memory totals)
    private
    returns (Balances.RateAcc memory)
  {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    uint256 rate = coverage.premiumRate.rayMul(exchangeRate());
    console.log('_afterBalanceUpdate0', coverage.premiumRate, rate, newExcess);

    rate = (rate * WadRayMath.RAY) / (newExcess + coverage.totalCovered + coverage.pendingCovered);

    console.log('_afterBalanceUpdate1', rate, coverage.totalCovered, coverage.pendingCovered);
    return _totalRate = totals.setRate(uint32(block.timestamp), rate);
  }

  function internalMintForCoverage(address account, uint256 coverageAmount) internal {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    uint256 excess = _excessCoverage;
    if (coverageAmount > 0 || excess > 0) {
      (uint256 newExcess, , ) = super.internalAddCoverage(coverageAmount + excess, type(uint256).max);
      if (newExcess != excess) {
        _excessCoverage = newExcess;
      }

      // TODO avoid update when rate doesn't change
      // if (params.premiumRateUpdated || excess != 0 || newExcess != 0) {
      totals = _afterBalanceUpdate(newExcess, totals);
    }

    uint256 amount = coverageAmount.rayDiv(exchangeRate()) + b.balance;
    require(amount == (b.balance = uint128(amount)));
    b.premiumBase = totals.accum;
    _balances[account] = b;
  }

  function internalBurn(address account, uint256 amount) internal returns (uint256 coverageAmount) {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);
    if (amount == type(uint256).max) {
      (amount, b.balance) = (b.balance, 0);
    } else {
      b.balance = uint128(b.balance - amount);
    }

    if (amount > 0) {
      coverageAmount = amount.rayMul(exchangeRate());
      _excessCoverage -= coverageAmount;
      totals = _afterBalanceUpdate(_excessCoverage, totals);
    }

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
        accumulated += uint256(b.balance).rayMul(premiumDiff);
      }
      return (uint256(b.balance).rayMul(totals.rate), accumulated);
    }

    return (0, accumulated);
  }

  function exchangeRate() public pure override returns (uint256) {
    return WadRayMath.RAY;
  }

  function statusOf(address account) external view returns (InsuredStatus) {
    return internalGetStatus(account);
  }

  function internalIsInvestor(address account) internal view override returns (bool) {
    UserBalance memory b = _balances[account];
    return b.premiumBase != 0 || b.balance != 0;
  }

  function internalGetStatus(address account) internal view override returns (InsuredStatus) {
    return super.internalGetInsuredStatus(account);
  }

  function internalSetStatus(address account, InsuredStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }

  modifier onlyActiveInsured() {
    require(internalGetStatus(msg.sender) == InsuredStatus.Accepted);
    _;
  }

  modifier onlyInsured() {
    require(internalGetStatus(msg.sender) > InsuredStatus.Unknown);
    _;
  }

  /// @dev ERC1363-like receiver, invoked by the collateral fund for transfers/investments from user.
  /// mints $IC tokens when $CC is received from a user
  function internalReceiveTransfer(
    address operator,
    address,
    uint256 value,
    bytes calldata data
  ) internal override onlyCollateralFund {
    if (internalIsInvestor(operator)) {
      if (value == 0) return;
      internalHandleInvestment(operator, value, data);
    } else {
      InsuredStatus status = internalGetStatus(operator);
      if (status != InsuredStatus.Unknown) {
        // TODO return of funds from insured
        Errors.notImplemented();
        return;
      }
    }
    internalHandleInvestment(operator, value, data);
  }

  function internalHandleInvestment(
    address investor,
    uint256 amount,
    bytes memory data
  ) internal virtual {
    if (data.length > 0) {
      abi.decode(data, ());
    }
    internalMintForCoverage(investor, amount);
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

  function internalPrepareJoin(address insured) internal override {
    WeightedPoolParams memory params = _params;
    InsuredParams memory insuredParams = IInsuredPool(insured).insuredParams();

    uint256 maxShare = uint256(insuredParams.riskWeightPct).percentDiv(params.riskWeightTarget);
    if (maxShare >= params.maxInsuredShare) {
      maxShare = params.maxInsuredShare;
    } else if (maxShare < params.minInsuredShare) {
      maxShare = params.minInsuredShare;
    }

    super.internalSetInsuredParams(
      insured,
      Rounds.InsuredParams({minUnits: insuredParams.minUnitsPerInsurer, maxShare: uint16(maxShare)})
    );
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
