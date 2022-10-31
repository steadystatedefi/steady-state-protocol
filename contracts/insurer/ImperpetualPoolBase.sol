// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ImperpetualPoolStorage.sol';
import './ImperpetualPoolExtension.sol';
import './WeightedPoolBase.sol';

/// @dev An implementation of insurer that allows partial release of investments / coverage (aka drawdown).
/// @dev It also implements a single-token model for its shares which allows the sencondary market (i.e. trading via DEX etc).
/// @dev The token of this pool does not change quantity, but gets higher value (exchange rate into CC) from premium flow.
abstract contract ImperpetualPoolBase is ImperpetualPoolStorage {
  using Math for uint256;
  using Math for uint128;
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

  /// @inheritdoc WeightedPoolBase
  function internalMintForCoverage(address account, uint256 value) internal override {
    (bool done, AddCoverageParams memory params, PartialState memory part) = _addCoverage(value);

    _mint(account, done ? value.rayDiv(exchangeRate(super.internalGetPremiumTotals(part, params.premium), value)) : 0, value);
  }

  /// @dev Adds subrogation as an excess to reduce gas cost of the operation.
  function internalSubrogated(uint256 value) internal override {
    internalSetExcess(_excessCoverage + value);
  }

  /// @dev A callback from self (PoolExtension) to keep code parts separate.
  /// @dev It handles cancellation of coverage, which includes termination of premium streaming, recovery of premium debt,
  /// @dev and split of the coverage escrow between this pool and the insured.
  /// @param insured is the cancelled policy.
  /// @param payoutValue value expected (approved) to be paid out as CC to the policy holder.
  /// @param advanceValue is value of coverage eligible to be escrowed considering the most recent state before the cancellation.
  /// @param recoveredValue is value of coverage allocated, but was not eligible to be escrowed, i.e. this coverage stays with the insurer now.
  /// @param premiumDebt is value of premium which was not pre-paid by the insured. It will be deducted from the payout.
  /// @return the value of coverage given to the insured from this insurer.
  function updateCoverageOnCancel(
    address insured,
    uint256 payoutValue,
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) external onlySelf returns (uint256) {
    uint256 forepayValue = subBalanceOfCollateral(insured);
    Sanity.require(advanceValue >= forepayValue);

    // a value this insurer has already credited to the insured
    uint256 v = forepayValue + premiumDebt;
    advanceValue += recoveredValue;

    uint256 premiumDebtRecovery;
    if (v >= payoutValue) {
      (recoveredValue, payoutValue) = advanceValue.boundedMaxSub(payoutValue);

      // the premium debt recovery is limited to the payout value, the payout value is deducted by the debt
      (payoutValue, premiumDebtRecovery) = payoutValue.boundedMaxSub(premiumDebt);
    } else {
      // payout is large and will cover whole premium debt
      premiumDebtRecovery = premiumDebt;
      payoutValue -= v;

      // max allowed drawdown of this insured
      uint256 insuredDrawdown = advanceValue - forepayValue;
      if (payoutValue > insuredDrawdown) {
        payoutValue = insuredDrawdown;
      }

      if (payoutValue != 0) {
        v = _calcAvailableDrawdownReserve(advanceValue);
        if (payoutValue > v) {
          payoutValue = v;
        }
      }

      payoutValue += forepayValue;
      recoveredValue = advanceValue - payoutValue - premiumDebt;
    }

    if (premiumDebt != 0) {
      // the outstanding premium debt is deducted as if it was paid out - this will reduce the total value
      Arithmetic.require((_burntPremium += uint128(premiumDebt)) >= premiumDebt);

      // the part of payout that was deducted and will be applied as value recovery
      if (premiumDebtRecovery != 0) {
        // it will be available as an extra coverage drawdown - this will increase the total value
        Arithmetic.require((_boostDrawdown += uint128(premiumDebtRecovery)) >= premiumDebtRecovery);
      }
    }

    Sanity.require(advanceValue == recoveredValue + premiumDebtRecovery + payoutValue);

    closeCollateralSubBalance(insured, payoutValue);

    if (recoveredValue > 0) {
      internalSetExcess(_excessCoverage + recoveredValue);
      internalOnCoverageRecovered();
    }

    return payoutValue;
  }

  /// @dev A callback from self (PoolExtension) to keep code parts separate.
  /// @dev It handles coverage on reconciliation - adds a portion of collateral into escrow for the insured.
  /// @param insured is the reconciled policy.
  /// @param receivedCoverage is a value of coverage allocated to the insured since the last reconcile (i.e. incremental).
  /// @param totalCovered is a total value of coverage allocated to the insured.
  /// @return the value/amount of collateral escrowed for the insured by this insurer.
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

  /// @inheritdoc WeightedPoolBase
  function pushCoverageExcess() public override {
    _addCoverage(0);
  }

  function totalSupplyValue(DemandedCoverage memory coverage, uint256 added) private view returns (uint256 v) {
    v = (coverage.totalCovered + _boostDrawdown) - _burntDrawdown;
    v += coverage.pendingCovered + _excessCoverage;
    v = v - added;
    v += coverage.totalPremium - _burntPremium;
  }

  /// @inheritdoc IInsurerToken
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

  /// @inheritdoc IInsurerToken
  function exchangeRate() public view override returns (uint256) {
    return exchangeRate(super.internalGetPremiumTotals(), 0);
  }

  /// @inheritdoc IERC20
  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
  }

  /// @inheritdoc IInsurerToken
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

    uint256 v = _boostDrawdown;
    if (v != 0) {
      (_boostDrawdown, v) = uint128(v).boundedXSub128(value);
    } else {
      v = value;
    }
    if (v != 0) {
      Arithmetic.require((_burntDrawdown += uint128(v)) >= v);
    }

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

  function _coverageDrawdown(uint256 totalCovered, uint16 maxDrawdownPct) internal view returns (uint256 max, uint256 avail) {
    max = totalCovered.percentMul(maxDrawdownPct);
    avail = max.boundedSub(_burntDrawdown);
  }

  /// @return maxAvail is a drawdown available in total
  function _calcAvailableDrawdownReserve(uint256 extra) internal view returns (uint256 maxAvail) {
    uint256 total = extra + _coveredTotal() + _excessCoverage;
    (, maxAvail) = _coverageDrawdown(total, PercentageMath.ONE - _params.coverageForepayPct);
  }

  /// @return max is a total drawdown allowed to users, it includes drawdown given out already.
  /// @return avail is a drawdown available to users now.
  function _calcAvailableUserDrawdown(uint256 totalCovered) internal view returns (uint256 max, uint256 avail) {
    (max, avail) = _coverageDrawdown(totalCovered + _excessCoverage, _params.maxUserDrawdownPct);
    max += totalCovered = _boostDrawdown;
    avail += totalCovered;
  }

  function internalCollectDrawdownPremium() internal override returns (uint256 maxDrawdownValue, uint256 availableDrawdownValue) {
    uint256 extYield = IManagedCollateralCurrency(collateral()).pullYield();
    if (extYield > 0) {
      Arithmetic.require((_boostDrawdown += uint128(extYield)) >= extYield);
    }
    return _calcAvailableUserDrawdown(_coveredTotal());
  }

  /// @dev a storage reserve for further upgrades
  uint256[16] private _gap;
}
