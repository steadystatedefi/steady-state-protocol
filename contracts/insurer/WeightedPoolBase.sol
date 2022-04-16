// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolExtension.sol';

// Handles all user-facing actions. Handles adding coverage (not demand) and tracking user tokens
abstract contract WeightedPoolBase is IInsurerPoolCore, WeightedPoolTokenStorage, Delegator, ERC1363ReceiverBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  address internal immutable _extension;

  event ExcessCoverageIncreased(uint256 coverageExcess);

  constructor(uint256 unitSize, WeightedPoolExtension extension) WeightedRoundsBase(unitSize) {
    require(extension.coverageUnitSize() == unitSize);
    _extension = address(extension);
  }

  // solhint-disable-next-line payable-fallback
  fallback() external {
    // all IInsurerPoolDemand etc functions should be delegated to the extension
    _delegate(_extension);
  }

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

  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
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

  ///@dev Attempt to take the excess coverage and fill batches. AKA if the pool is full, a user deposits and then
  /// an insured adds more demand
  function pushCoverageExcess() public {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage == 0) {
      return;
    }

    (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part) = super.internalAddCoverage(excessCoverage, type(uint256).max);

    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();
    _excessCoverage = newExcess;
    _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, p.premium));
  }

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

  function balanceOf(address account) public view override returns (uint256) {
    return uint256(_balances[account].balance).rayMul(exchangeRate());
  }

  ///@dev returns the ($CC coverage, $PC coverage, premium accumulated) of a user
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

  function totalSupply() public view override returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered + _excessCoverage;
  }

  /// @dev Returns the current rate that this user earns per-block, and the amount of premium accumulated
  function interestOf(address account) public view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = _beforeAnyBalanceUpdate();
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

  function exchangeRate() public view override(IInsurerPoolCore, WeightedPoolStorage) returns (uint256) {
    return WeightedPoolStorage.exchangeRate();
  }

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
