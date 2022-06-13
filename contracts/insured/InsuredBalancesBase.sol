// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import '../insurance/InsurancePoolBase.sol';

import 'hardhat/console.sol';

/// @title Insured Balances Base
/// @notice Holds balances of how much Insured owes to each Insurer in terms of rate
/// @dev Calculates retroactive premium paid by Insured to Insurer over-time.
/// @dev Insured pool tokens = investment * premium rate (e.g $1000 @ 5% premium = 50 tokens)
abstract contract InsuredBalancesBase is InsurancePoolBase, ERC20BalancelessBase, IPremiumCalculator {
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;
  using Balances for Balances.RateAccWithUint16;

  mapping(address => Balances.RateAccWithUint16) private _balances;
  Balances.RateAcc private _totals;

  uint32 private _cancelledAt; // TODO

  function _ensureHolder(uint16 flags) private view {
    require(internalIsAllowedAsHolder(flags));
  }

  function _ensureHolder(address account) internal view {
    _ensureHolder(_balances[account].extra);
  }

  /// @dev Mint the correct amount of tokens for the account (investor)
  /// @param account Account to mint to
  /// @param rateAmount Amount of coverage provided
  /// @param premiumRate Rate paid on the amount
  function internalMintForCoverage(
    address account,
    uint256 rateAmount,
    uint256 premiumRate
  ) internal virtual {
    rateAmount = rateAmount.wadMul(premiumRate);
    require(rateAmount <= type(uint88).max);

    Balances.RateAccWithUint16 memory b = _syncBalance(account);
    _ensureHolder(b.extra);

    emit Transfer(address(0), account, rateAmount);

    b.rate += uint88(rateAmount);
    _balances[account] = b;

    Balances.RateAcc memory totals = internalSyncTotals();

    rateAmount += totals.rate;
    require((totals.rate = uint96(rateAmount)) == rateAmount);

    _totals = totals;
  }

  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    Balances.RateAccWithUint16 memory b = _syncBalance(sender);
    b.rate = uint88(b.rate - amount);
    _balances[sender] = b;

    b = _syncBalance(recipient);
    b.rate += uint88(amount);
    _balances[recipient] = b;
  }

  function internalIsAllowedAsHolder(uint16 status) internal view virtual returns (bool);

  /// @dev Cancel this policy
  function internalCancelRates() internal {
    require(_cancelledAt == 0);
    _cancelledAt = uint32(block.timestamp);
  }

  /// @dev Return timestamp or time that the cancelled state occurred
  function _syncTimestamp() private view returns (uint32) {
    uint32 ts = _cancelledAt;
    return ts > 0 ? ts : uint32(block.timestamp);
  }

  /// @dev Update premium paid of entire pool
  function internalSyncTotals() internal view returns (Balances.RateAcc memory) {
    return _totals.sync(_syncTimestamp());
  }

  /// @dev Update premium paid to an account
  function _syncBalance(address account) private view returns (Balances.RateAccWithUint16 memory b) {
    return _balances[account].sync(_syncTimestamp());
  }

  /// @notice Balance of the account, which is the rate paid to it
  /// @param account The account to query
  /// @return Rate paid to this account
  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].rate;
  }

  /// @notice Balance and total accumulated of the account
  /// @param account The account to query
  /// @return rate The rate paid to this account
  /// @return premium The total premium paid to this account
  function balancesOf(address account) public view returns (uint256 rate, uint256 premium) {
    Balances.RateAccWithUint16 memory b = _syncBalance(account);
    return (b.rate, b.accum);
  }

  /// @notice Total Supply - also the current premium rate
  /// @return The total premium rate
  function totalSupply() public view override returns (uint256) {
    return _totals.rate;
  }

  /// @notice Total Premium rate and accumulated
  /// @return rate The current rate paid by the insured
  /// @return accumulated The total amount of premium paid
  function totalPremium() public view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = internalSyncTotals();
    return (totals.rate, totals.accum);
  }

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual {
    require(status > 0);
    if (_balances[account].extra == 0) {
      require(Address.isContract(account));
    }
    _balances[account].extra = status;
  }

  function getAccountStatus(address account) internal view virtual returns (uint16) {
    return _balances[account].extra;
  }

  /// @dev Reconcile the amount of collected premium and current premium rate with the Insurer
  /// @param insurer The insurer to reconcile with
  /// @param updateRate Whether the total rate of this Insured pool should be updated
  /// @return receivedCoverage Amount of new coverage provided since the last reconcilation
  /// @return receivedCollateral Amount of collateral currency received during this reconcilation (<= receivedCoverage)
  /// @return coverage The new information on coverage demanded, provided and premium paid
  function internalReconcileWithInsurer(IInsurerPoolDemand insurer, bool updateRate)
    internal
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
      DemandedCoverage memory coverage
    )
  {
    Balances.RateAccWithUint16 memory b = _syncBalance(address(insurer));
    _ensureHolder(b.extra);

    (receivedCoverage, receivedCollateral, coverage) = insurer.receiveDemandedCoverage(address(this));
    // console.log('internalReconcileWithInsurer', address(this), coverage.totalPremium, coverage.premiumRate);

    uint256 diff;
    Balances.RateAcc memory totals;
    if (b.accum != coverage.totalPremium) {
      totals = internalSyncTotals();
      if (b.accum < coverage.totalPremium) {
        // technical underpayment
        diff = coverage.totalPremium - b.accum;
        diff += totals.accum;
        require((totals.accum = uint128(diff)) == diff);
        revert('technical underpayment'); // TODO this should not happen now, but remove it later
      } else {
        totals.accum -= uint128(diff = b.accum - coverage.totalPremium); // TODO (Tyler)
      }

      b.accum = uint120(coverage.totalPremium);
    }

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate || updateRate)) {
      if (diff == 0) {
        totals = internalSyncTotals();
        diff = 1;
      }
      uint88 prevRate = b.rate;
      require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
      if (prevRate > b.rate) {
        totals.rate -= prevRate - b.rate;
      } else {
        totals.rate += b.rate - prevRate;
      }
    }

    if (diff > 0) {
      _totals = totals;
      _balances[address(insurer)] = b;
    }
  }

  /// @dev Do the same as `internalReconcileWithInsurer` but only as a view, don't make changes
  function internalReconcileWithInsurerView(IInsurerPoolDemand insurer, Balances.RateAcc memory totals)
    internal
    view
    returns (
      uint256 receivedCoverage,
      DemandedCoverage memory coverage,
      Balances.RateAccWithUint16 memory b
    )
  {
    b = _syncBalance(address(insurer));
    _ensureHolder(b.extra);

    (receivedCoverage, coverage) = insurer.receivableDemandedCoverage(address(this));
    require(b.updatedAt >= coverage.premiumUpdatedAt);

    uint256 diff;
    if (b.accum != coverage.totalPremium) {
      if (b.accum < coverage.totalPremium) {
        // technical underpayment
        diff = coverage.totalPremium - b.accum;
        diff += totals.accum;
        require((totals.accum = uint128(diff)) == diff);
        revert('technical underpayment'); // TODO this should not happen now, but remove it later
      } else {
        diff = b.accum - coverage.totalPremium;
        totals.accum -= uint128(diff);
      }

      b.accum = uint120(coverage.totalPremium);
    }

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate)) {
      require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
    }
  }
}
