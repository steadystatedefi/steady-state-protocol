// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ImperpetualPoolStorage.sol';
import './ImperpetualPoolExtension.sol';
import './WeightedPoolBase.sol';

/// @title Index Pool Base with Perpetual Index Pool Tokens
/// @notice Handles adding coverage by users.
abstract contract ImperpetualPoolBase is ImperpetualPoolStorage {
  using Math for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(ImperpetualPoolExtension extension, JoinablePoolExtension joinExtension) WeightedPoolBase(extension, joinExtension) {}

  function _addCoverage(uint256 value)
    private
    returns (
      bool done,
      AddCoverageParams memory params,
      PartialState memory part
    )
  {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage > 0 || value > 0) {
      uint256 newExcess;
      uint256 loopLimit;
      (newExcess, loopLimit, params, part) = super.internalAddCoverage(value + excessCoverage, defaultLoopLimit(LoopLimitType.AddCoverage, 0));

      if (newExcess != excessCoverage) {
        internalSetExcess(newExcess);
      }

      internalAutoPullDemand(params, loopLimit, newExcess > 0, value);

      done = true;
    }
  }

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  /// @dev Update the new amount of excess coverage
  function internalMintForCoverage(address account, uint256 value) internal override {
    (bool done, AddCoverageParams memory params, PartialState memory part) = _addCoverage(value);

    // TODO:TEST test adding coverage to an empty pool
    _mint(account, done ? value.rayDiv(exchangeRate(super.internalGetPremiumTotals(part, params.premium), value)) : 0, value);
  }

  function internalSubrogated(uint256 value) internal override {
    internalSetExcess(_excessCoverage + value);
  }

  function updateCoverageOnCancel(
    address insured,
    uint256 payoutValue,
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) external onlySelf returns (uint256) {
    Value.require(advanceValue >= subBalanceOfCollateral(insured));

    advanceValue = advanceValue + recoveredValue;

    // a value this insurer has already credited to the insured
    uint256 givenValue = advanceValue + premiumDebt;

    uint256 premiumDebtRecovery;
    // the outstanding premium debt is deducted as if it was paid out - this will reduce the total value (but it can be recovered, see below)
    if (premiumDebt > 0) {
      Arithmetic.require((_burntPremium += uint128(premiumDebt)) >= premiumDebt);
    }

    if (givenValue > payoutValue) {
      recoveredValue = advanceValue.boundedSub(payoutValue);

      // the premium debt recovery is limited to the payout value, the payout value is deducted by the debt
      (payoutValue, premiumDebtRecovery) = payoutValue.boundedMaxSub(premiumDebt);
    } else if (givenValue < payoutValue) {
      premiumDebtRecovery = premiumDebt;
      payoutValue -= premiumDebt;

      uint256 underpay = payoutValue - advanceValue;
      if (underpay > 0 && underpay > (recoveredValue = _calcAvailableDrawdownReserve(advanceValue))) {
        underpay = recoveredValue;
      }
      recoveredValue = 0;

      payoutValue = advanceValue + underpay;
    }

    if (premiumDebtRecovery > 0) {
      // the part of payout that was deducted and will be applied as value recovery
      // it will be available as an extra coverage drawdown - this will increase the total value
      _deltaDrawdown += premiumDebtRecovery.asInt128();
    }

    closeCollateralSubBalance(insured, payoutValue);

    if (recoveredValue > 0) {
      internalSetExcess(_excessCoverage + recoveredValue);
      internalOnCoverageRecovered();
    }

    return payoutValue;
  }

  function updateCoverageOnReconcile(
    address insured,
    uint256 receivedCoverage,
    uint256 totalCovered
  ) external onlySelf returns (uint256) {
    uint256 expectedAmount = totalCovered.percentMul(_params.coverageForepayPct);
    uint256 actualAmount = subBalanceOfCollateral(insured);

    if (actualAmount < expectedAmount) {
      uint256 d = expectedAmount - actualAmount;
      if (d < receivedCoverage) {
        receivedCoverage = d;
      }
      if ((d = balanceOfCollateral(address(this))) < receivedCoverage) {
        receivedCoverage = d;
      }

      if (receivedCoverage > 0) {
        transferCollateral(insured, receivedCoverage);
      }
    } else {
      receivedCoverage = 0;
    }

    return receivedCoverage;
  }

  /// @dev Attempt to take the excess coverage and fill batches
  /// @dev Occurs when there is excess and a new batch is ready (more demand added)
  function pushCoverageExcess() public override {
    _addCoverage(0);
  }

  function totalSupplyValue(DemandedCoverage memory coverage, uint256 added) private view returns (uint256 v) {
    v = coverage.totalCovered.addInt(_deltaDrawdown);
    v += coverage.pendingCovered + _excessCoverage;
    v = v - added;
    v += coverage.totalPremium - _burntPremium;
  }

  function totalSupplyValue() public view returns (uint256) {
    return totalSupplyValue(super.internalGetPremiumTotals(), 0);
  }

  function exchangeRate(DemandedCoverage memory coverage, uint256 added) private view returns (uint256 v) {
    if ((v = totalSupply()) > 0) {
      v = totalSupplyValue(coverage, added).rayDiv(v);
    } else {
      v = WadRayMath.RAY;
    }
  }

  function exchangeRate() public view override returns (uint256 v) {
    return exchangeRate(super.internalGetPremiumTotals(), 0);
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
  }

  function balancesOf(address account)
    public
    view
    returns (
      uint256 value,
      uint256 balance,
      uint256 swappable
    )
  {
    balance = balanceOf(account);
    swappable = value = balance.rayMul(exchangeRate());
  }

  ///@notice Transfer a balance to a recipient, syncs the balances before performing the transfer
  ///@param sender  The sender
  ///@param recipient The receiver
  ///@param amount  Amount to transfer
  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    _balances[sender].balance = uint128(_balances[sender].balance - amount);
    _balances[recipient].balance += uint128(amount);
  }

  function _burnValue(
    address account,
    uint256 value,
    DemandedCoverage memory coverage
  ) private returns (uint256 burntAmount) {
    _burn(account, burntAmount = value.rayDiv(exchangeRate(coverage, 0)), value);
  }

  function _burnPremium(
    address account,
    uint256 value,
    DemandedCoverage memory coverage
  ) internal returns (uint256 burntAmount) {
    Value.require(coverage.totalPremium >= _burntPremium + value);
    burntAmount = _burnValue(account, value, coverage);
    _burntPremium += value.asUint128();
  }

  function _burnCoverage(
    address account,
    uint256 value,
    address recepient,
    DemandedCoverage memory coverage
  ) internal returns (uint256 burntAmount) {
    // NB! removed for performance reasons - use carefully
    // Value.require(value <= _calcAvailableUserDrawdown(totalCovered + pendingCovered));

    burntAmount = _burnValue(account, value, coverage);

    _deltaDrawdown -= value.asInt128();
    transferCollateral(recepient, value);
  }

  function internalBurnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) internal override {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    drawdownRecepient != address(0) ? _burnCoverage(account, value, drawdownRecepient, coverage) : _burnPremium(account, value, coverage);
  }

  function __calcDrawdown(uint256 totalCovered, uint16 maxDrawdownPct) internal view returns (uint256 max, uint256 avail) {
    max = (totalCovered + _excessCoverage).percentMul(maxDrawdownPct);
    avail = max.boundedAddInt(_deltaDrawdown);
  }

  function _calcAvailableDrawdownReserve(uint256 extra) internal view returns (uint256 avail) {
    (, avail) = __calcDrawdown(_coveredTotal() + extra, PercentageMath.ONE - _params.coverageForepayPct);
  }

  function _calcAvailableUserDrawdown(uint256 totalCovered) internal view returns (uint256 max, uint256 avail) {
    return __calcDrawdown(totalCovered, _params.maxUserDrawdownPct);
  }

  function internalCollectDrawdownPremium() internal override returns (uint256 maxDrawdownValue, uint256 availableDrawdownValue) {
    uint256 extYield = IManagedCollateralCurrency(collateral()).pullYield();
    if (extYield > 0) {
      _deltaDrawdown += extYield.asInt128();
    }
    return _calcAvailableUserDrawdown(_coveredTotal());
  }
}
