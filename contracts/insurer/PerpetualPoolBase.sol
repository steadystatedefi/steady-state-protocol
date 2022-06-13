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

  function premiumHandler() public view returns (address) {
    return _premiumHandler;
  }

  function internalSetPoolParams(WeightedPoolParams memory params) internal override {
    require(params.maxDrawdownInverse == PercentageMath.ONE);

    super.internalSetPoolParams(params);
  }

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  /// @dev Update the new amount of excess coverage
  function _mintForCoverage(address account, uint256 coverageValue) private {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    uint256 excessCoverage = _excessCoverage;
    if (coverageValue > 0 || excessCoverage > 0) {
      (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part) = super.internalAddCoverage(
        coverageValue + excessCoverage,
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

    emit Transfer(address(0), account, coverageValue);

    uint256 amount = coverageValue.rayDiv(exchangeRate()) + b.balance;
    require(amount == (b.balance = uint128(amount)));
    _balances[account] = b;
  }

  function internalAdjustCoverage(uint256 loss, uint256 excess) private {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();

    uint256 excessCoverage = _excessCoverage + excess;
    if (loss > 0) {
      uint256 total = coverage.totalCovered + coverage.pendingCovered + excessCoverage;
      _inverseExchangeRate = WadRayMath.RAY - total.rayDiv(total + loss).rayMul(exchangeRate());
    }

    if (excess > 0) {
      _excessCoverage = excessCoverage;
      emit ExcessCoverageIncreased(excessCoverage);
    }
    _afterBalanceUpdate(excessCoverage, totals, coverage);
  }

  function internalSubrogate(uint256 value) private {
    if (value > 0) {
      internalAdjustCoverage(0, value);
      internalOnCoverageRecovered();
    }
  }

  /// @dev Update the exchange rate and excess coverage when a policy cancellation occurs
  /// @dev Call _afterBalanceUpdate to update the rate of the pool
  function updateCoverageOnCancel(uint256 paidoutCoverage, uint256 excess) public {
    require(msg.sender == address(this));

    internalAdjustCoverage(paidoutCoverage, excess);

    if (excess > 0) {
      internalOnCoverageRecovered();
    }
  }

  function internalOnCoverageRecovered() internal virtual {
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
      totals = _afterBalanceUpdate(_excessCoverage -= coverageValue, totals, super.internalGetPremiumTotals());
    }
    emit Transfer(account, address(0), coverageValue);
    _balances[account] = b;

    transferCollateral(account, coverageValue);

    return coverageValue;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
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
    scaled = balanceOf(account);
    coverage = scaled.rayMul(exchangeRate());
    (, premium) = interestOf(account);
  }

  /// @notice The amount of coverage ($CC) that has been allocated to this pool
  /// @return The $CC allocated to this pool
  function totalSupplyValue() public view returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered + _excessCoverage;
  }

  /// @notice The amount of coverage ($CC) that has been allocated to this pool
  /// @return The $CC allocated to this pool
  function totalSupply() public view override returns (uint256) {
    return totalSupplyValue().rayDiv(exchangeRate());
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
    return internalStatusOf(account);
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
      uint256 bal = balanceOf(account).rayMul(exchangeRate());
      if (amount > bal) {
        amount = bal;
      }
    }
  }

  function withdrawAll() external override returns (uint256) {
    return internalBurn(msg.sender, _excessCoverage);
  }
}
