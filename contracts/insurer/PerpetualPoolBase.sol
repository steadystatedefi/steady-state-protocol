// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import './PerpetualPoolStorage.sol';
import './PerpetualPoolExtension.sol';
import './WeightedPoolBase.sol';

/// @title Index Pool Base with Perpetual Index Pool Tokens
/// @notice Handles adding coverage by users.
abstract contract PerpetualPoolBase is IPerpetualInsurerPool, PerpetualPoolStorage, WeightedPoolBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(uint256 unitSize, PerpetualPoolExtension extension) WeightedRoundsBase(unitSize) WeightedPoolBase(unitSize, extension) {}

  function internalSetPoolParams(WeightedPoolParams memory params) internal override {
    require(params.maxDrawdown == 0);

    super.internalSetPoolParams(params);
  }

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  /// @dev Update the new amount of excess coverage
  function _mintForCoverage(address account, uint256 coverageAmount) private {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    uint256 excessCoverage = _excessCoverage;
    if (coverageAmount > 0 || excessCoverage > 0) {
      (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part) = super.internalAddCoverage(
        coverageAmount + excessCoverage,
        type(uint256).max
      );

      if (newExcess != excessCoverage) {
        _excessCoverage = newExcess;
        if (newExcess > excessCoverage) {
          emit ExcessCoverageIncreased(newExcess);
        }
      }

      _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, p.premium));
    }

    emit Transfer(address(0), account, coverageAmount);

    uint256 amount = coverageAmount.rayDiv(exchangeRate()) + b.balance;
    require(amount == (b.balance = uint128(amount)));
    _balances[account] = b;
  }

  /// @dev Update the exchange rate and excess coverage when a policy cancellation occurs
  /// @dev Call _afterBalanceUpdate to update the rate of the pool
  function updateCoverageOnCancel(uint256 paidoutCoverage, uint256 excess) public {
    require(msg.sender == address(this));

    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();

    uint256 excessCoverage = _excessCoverage + excess;
    if (paidoutCoverage > 0) {
      uint256 total = coverage.totalCovered + coverage.pendingCovered + excessCoverage;
      _inverseExchangeRate = WadRayMath.RAY - total.rayDiv(total + paidoutCoverage).rayMul(exchangeRate());
    }

    if (excess > 0) {
      _excessCoverage = excessCoverage;
      emit ExcessCoverageIncreased(excessCoverage);
    }
    _afterBalanceUpdate(excessCoverage, totals, coverage);

    internalPostCoverageCancel();
  }

  function internalPostCoverageCancel() internal virtual {
    pushCoverageExcess();
  }

  /// @dev Attempt to take the excess coverage and fill batches
  /// @dev Occurs when there is excess and a new batch is ready (more demand added)
  function pushCoverageExcess() public override {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage == 0) {
      return;
    }

    (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part) = super.internalAddCoverage(excessCoverage, type(uint256).max);

    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();
    _excessCoverage = newExcess;
    _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, p.premium));
  }

  /// @dev Burn a user's pool tokens and send them the underlying $CC in return
  function internalBurn(address account, uint256 coverageAmount) internal returns (uint256) {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    {
      uint256 balance = uint256(b.balance).rayMul(exchangeRate());
      if (coverageAmount >= balance) {
        coverageAmount = balance;
        b.balance = 0;
      } else {
        b.balance = uint128(b.balance - coverageAmount.rayDiv(exchangeRate()));
      }
    }

    if (coverageAmount > 0) {
      totals = _afterBalanceUpdate(_excessCoverage -= coverageAmount, totals, super.internalGetPremiumTotals());
    }
    emit Transfer(account, address(0), coverageAmount);
    _balances[account] = b;

    transferCollateral(account, coverageAmount);

    return coverageAmount;
  }

  /// TODO
  function balanceOf(address account) public view override returns (uint256) {
    return uint256(_balances[account].balance).rayMul(exchangeRate());
  }

  /// @dev returns the ($CC coverage, $PC coverage, premium accumulated) of a user
  /// @return coverage The amount of coverage user is providing
  /// @return scaled The number of tokens `coverage` is equal to
  /// @return premium The amount of premium earned by the user
  function balancesOf(address account)
    public
    view
    returns (
      uint256 coverage,
      uint256 scaled,
      uint256 premium
    )
  {
    scaled = scaledBalanceOf(account);
    coverage = scaled.rayMul(exchangeRate());
    (, premium) = interestOf(account);
  }

  function scaledBalanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
  }

  /// @notice The amount of coverage ($CC) that has been allocated to this pool
  /// @return The $CC allocated to this pool
  function totalSupply() public view override returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered + _excessCoverage;
  }

  function interestOf(address account) public view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();
    UserBalance memory b = _balances[account];

    accumulated = _premiums[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.extra;
      if (premiumDiff > 0) {
        accumulated += uint256(b.balance).rayMul(premiumDiff);
      }
      return (uint256(b.balance).rayMul(totals.rate), accumulated);
    }

    return (0, accumulated);
  }

  function exchangeRate() public view override(IInsurerPoolCore, PerpetualPoolStorage) returns (uint256) {
    return PerpetualPoolStorage.exchangeRate();
  }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function statusOf(address account) external view returns (InsuredStatus status) {
    if ((status = internalGetStatus(account)) == InsuredStatus.Unknown && internalIsInvestor(account)) {
      status = InsuredStatus.NotApplicable;
    }
    return status;
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
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(sender);

    b.balance = uint128(b.balance - amount);
    _balances[sender] = b;

    b = _syncBalance(recipient, totals);
    amount += b.balance;
    require((b.balance = uint128(amount)) == amount);
    _balances[recipient] = b;
  }

  ///
  function internalReceiveTransfer(
    address operator,
    address account,
    uint256 amount,
    bytes calldata data
  ) internal override onlyCollateralCurrency {
    require(data.length == 0);
    require(operator != address(this) && account != address(this) && internalGetStatus(account) == InsuredStatus.Unknown);

    _mintForCoverage(account, amount);
  }

  /// @dev Max amount withdrawable is the amount of excess coverage
  function withdrawable(address account) public view override returns (uint256 amount) {
    amount = _excessCoverage;
    if (amount > 0) {
      uint256 bal = balanceOf(account);
      if (amount > bal) {
        amount = bal;
      }
    }
  }

  function withdrawAll() external override returns (uint256) {
    return internalBurn(msg.sender, _excessCoverage);
  }

  // function getUnadjusted()
  //   external
  //   view
  //   returns (
  //     uint256 total,
  //     uint256 pendingCovered,
  //     uint256 pendingDemand
  //   )
  // {
  //   return internalGetUnadjustedUnits();
  // }

  // function applyAdjustments() external {
  //   internalApplyAdjustmentsToTotals();
  // }
}
