// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './PerpetualPoolStorage.sol';
import './PerpetualPoolExtension.sol';
import './WeightedPoolBase.sol';

/// @dev An implementation of insurer that does NOT allow release of investments / coverage.
/// @dev It implements a dual-token model where the 2nd token represents the accumulated premium value.
/// @dev This model is NOT suitable for the sencondary market as it will cause the premium value to be accumulated on a DEX contract.
abstract contract PerpetualPoolBase is IPerpetualInsurerPool, PerpetualPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(PerpetualPoolExtension extension, JoinablePoolExtension joinExtension) WeightedPoolBase(extension, joinExtension) {}

  /// @inheritdoc WeightedPoolBase
  function internalMintForCoverage(address account, uint256 coverageValue) internal override {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    uint256 excessCoverage = _excessCoverage;
    if (coverageValue > 0 || excessCoverage > 0) {
      (uint256 newExcess, uint256 loopLimit, AddCoverageParams memory params, PartialState memory part) = super.internalAddCoverage(
        coverageValue + excessCoverage,
        defaultLoopLimit(LoopLimitType.AddCoverage, 0)
      );

      if (newExcess != excessCoverage) {
        internalSetExcess(newExcess);
      }

      _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, params.premium));

      internalAutoPullDemand(params, loopLimit, newExcess > 0, coverageValue);
    }

    emit Transfer(address(0), account, coverageValue);

    uint256 amount = coverageValue.rayDiv(exchangeRate()) + b.balance;
    Arithmetic.require(amount == (b.balance = uint128(amount)));
    _balances[account] = b;
  }

  /// @dev Handles loss and excess of coverage
  function internalAdjustCoverage(uint256 loss, uint256 excess) private {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();

    uint256 excessCoverage = _excessCoverage + excess;
    if (loss > 0) {
      uint256 total = coverage.totalCovered + coverage.pendingCovered + excessCoverage;
      _inverseExchangeRate = WadRayMath.RAY - total.rayDiv(total + loss).rayMul(exchangeRate());
    }

    if (excess > 0) {
      internalSetExcess(excessCoverage);
    }
    _afterBalanceUpdate(excessCoverage, totals, coverage);
  }

  function internalSubrogated(uint256 value) internal override {
    internalAdjustCoverage(0, value);
  }

  /// @dev A callback from self (PoolExtension) to keep code parts separate.
  /// @dev It handles cancellation of coverage, which includes recovery of premium debt and adjustments to coverage on losses.
  /// @param valueLoss is a loss of the pool's value, e.g. payout to the policy holder.
  /// @param excess is a value made available for coverage.
  /// @param collateralAsPremium is value of coverage to be given out as premium because of premium debt of an insured.
  function updateCoverageOnCancel(
    uint256 valueLoss,
    uint256 excess,
    uint256 collateralAsPremium
  ) external onlySelf {
    internalAdjustCoverage(valueLoss, excess);
    if (collateralAsPremium > 0) {
      internalAddCollateralAsPremium(collateralAsPremium);
    }
    if (excess > 0) {
      internalOnCoverageRecovered();
    }
  }

  function internalAddCollateralAsPremium(uint256 amount) internal virtual {
    amount;
    // TODO internalAddCollateralAsPremium
    Errors.notImplemented();
  }

  /// @inheritdoc WeightedPoolBase
  function pushCoverageExcess() public override {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage == 0) {
      return;
    }

    (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part) = super.internalAddCoverage(excessCoverage, type(uint256).max);

    if (newExcess != excessCoverage) {
      Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();
      internalSetExcess(newExcess);
      _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, p.premium));
    }
  }

  /// @dev Burn a user's pool tokens and send them the underlying $CC in return
  function internalBurn(address account, uint256 coverageValue) internal returns (uint256) {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    {
      uint256 balance = uint256(b.balance).rayMul(exchangeRate());
      if (coverageValue >= balance) {
        coverageValue = balance;
        b.balance = 0;
      } else {
        b.balance = uint128(b.balance - coverageValue.rayDiv(exchangeRate()));
      }
    }

    if (coverageValue > 0) {
      uint256 excess = _excessCoverage - coverageValue;
      internalSetExcess(excess);
      totals = _afterBalanceUpdate(excess, totals, super.internalGetPremiumTotals());
    }
    emit Transfer(account, address(0), coverageValue);
    _balances[account] = b;

    transferCollateral(account, coverageValue);

    return coverageValue;
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
    value = balance.rayMul(exchangeRate());
    (, swappable) = interestOf(account);
  }

  /// @inheritdoc IInsurerToken
  function totalSupplyValue() public view returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered + _excessCoverage;
  }

  /// @inheritdoc IERC20
  function totalSupply() public view override returns (uint256) {
    return totalSupplyValue().rayDiv(exchangeRate());
  }

  /// @inheritdoc IPerpetualInsurerPool
  function interestOf(address account) public view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();
    UserBalance memory b = _balances[account];

    accumulated = _userPremiums[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.extra;
      if (premiumDiff > 0) {
        accumulated += uint256(b.balance).rayMul(premiumDiff);
      }
      return (uint256(b.balance).rayMul(totals.rate), accumulated);
    }

    return (0, accumulated);
  }

  /// @inheritdoc IInsurerToken
  function exchangeRate() public view override(IInsurerToken, PerpetualPoolStorage) returns (uint256) {
    return PerpetualPoolStorage.exchangeRate();
  }

  ///@dev Transfer a balance to a recipient, syncs the balances before performing the transfer
  ///@param sender  The sender
  ///@param recipient The receiver
  ///@param amount  Amount to transfer
  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(sender);

    b.balance = uint128(b.balance - amount);
    _balances[sender] = b;

    b = _syncBalance(recipient, totals);
    Arithmetic.require((b.balance += uint128(amount)) >= amount);
    _balances[recipient] = b;
  }

  /// @inheritdoc IPerpetualInsurerPool
  function withdrawable(address account) public view override returns (uint256 amount) {
    amount = _excessCoverage;
    if (amount > 0) {
      uint256 bal = balanceOf(account).rayMul(exchangeRate());
      if (amount > bal) {
        amount = bal;
      }
    }
  }

  /// @inheritdoc IPerpetualInsurerPool
  function withdrawAll() external override onlyUnpaused returns (uint256) {
    return internalBurn(msg.sender, _excessCoverage);
  }

  function internalBurnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) internal override {
    if (drawdownRecepient == address(0)) {
      (UserBalance memory b, ) = _beforeBalanceUpdate(account);
      b.extra = uint128(b.extra - value);
      _balances[account] = b;
    } else {
      _burnDrawdown(account, value);
    }
  }

  function _burnDrawdown(address account, uint256 value) private {
    account;
    value;
    Errors.notImplemented();
  }

  function internalCollectDrawdownPremium() internal view override returns (uint256 maxDrawdownValue, uint256 availableDrawdownValue) {}

  function internalSetPoolParams(WeightedPoolParams memory params) internal override {
    Value.require(params.coverageForepayPct == PercentageMath.ONE);

    super.internalSetPoolParams(params);
  }

  /// @dev a storage reserve for further upgrades
  uint256[16] private _gap;
}
