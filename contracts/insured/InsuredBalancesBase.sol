// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../interfaces/ICoverageDistributor.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import '../funds/Collateralized.sol';

import 'hardhat/console.sol';

/// @title Insured Balances Base
/// @notice Holds balances of how much Insured owes to each Insurer in terms of rate
/// @dev Calculates retroactive premium paid by Insured to Insurer over-time.
/// @dev Insured pool tokens = investment * premium rate (e.g $1000 @ 5% premium = 50 tokens)
abstract contract InsuredBalancesBase is Collateralized, ERC20BalancelessBase {
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;
  using Balances for Balances.RateAccWithUint16;

  mapping(address => Balances.RateAccWithUint16) private _balances;
  Balances.RateAcc private _totalAllocatedDemand;

  uint32 private _cancelledAt;

  function _ensureHolder(uint16 flags) private view {
    Access.require(internalIsAllowedAsHolder(flags));
  }

  function _ensureHolder(address account) internal view {
    _ensureHolder(_balances[account].extra);
  }

  function _beforeMintOrBurn(address account) internal view returns (Balances.RateAccWithUint16 memory b, Balances.RateAcc memory totals) {
    b = _syncBalance(account);
    _ensureHolder(b.extra);
    totals = internalSyncTotals();
  }

  // slither-disable-next-line costly-loop
  function _afterMintOrBurn(
    address account,
    Balances.RateAccWithUint16 memory b,
    Balances.RateAcc memory totals
  ) internal {
    _balances[account] = b;
    _totalAllocatedDemand = totals;
  }

  /// @dev Mint the correct amount of tokens for the account (investor)
  /// @param account Account to mint to
  /// @param rateAmount Amount of rate
  // slither-disable-next-line costly-loop
  function internalMintForDemandedCoverage(address account, uint256 rateAmount) internal {
    (Balances.RateAccWithUint16 memory b, Balances.RateAcc memory totals) = _beforeMintOrBurn(account);

    Arithmetic.require((b.rate += uint88(rateAmount)) >= rateAmount);
    Arithmetic.require((totals.rate += uint96(rateAmount)) >= rateAmount);

    _afterMintOrBurn(account, b, totals);
    emit Transfer(address(0), address(account), rateAmount);
  }

  function internalBurnForDemandedCoverage(address account, uint256 rateAmount) internal {
    (Balances.RateAccWithUint16 memory b, Balances.RateAcc memory totals) = _beforeMintOrBurn(account);

    b.rate = uint88(b.rate - rateAmount);
    totals.rate = uint96(totals.rate - rateAmount);

    _afterMintOrBurn(account, b, totals);
    emit Transfer(address(account), address(0), rateAmount);
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
    State.require(_cancelledAt == 0);
    _cancelledAt = uint32(block.timestamp);
  }

  /// @dev Return timestamp or time that the cancelled state occurred
  function _syncTimestamp() private view returns (uint32) {
    uint32 ts = _cancelledAt;
    return ts > 0 ? ts : uint32(block.timestamp);
  }

  /// @dev Update premium paid of entire pool
  function internalExpectedTotals(uint32 at) internal view returns (Balances.RateAcc memory) {
    Value.require(at >= block.timestamp);
    uint32 ts = _cancelledAt;
    return _totalAllocatedDemand.sync(ts > 0 && ts <= at ? ts : at);
  }

  /// @dev Update premium paid of entire pool
  function internalSyncTotals() internal view returns (Balances.RateAcc memory) {
    return _totalAllocatedDemand.sync(_syncTimestamp());
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
    return _totalAllocatedDemand.rate;
  }

  /// @notice Total Premium rate and accumulated
  /// @return rate The current rate paid by the insured
  /// @return accumulated The total amount of premium to be paid for the policy
  function totalPremium() public view returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = internalSyncTotals();
    return (totals.rate, totals.accum);
  }

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual {
    Value.require(status > 0);
    if (_balances[account].extra == 0) {
      Value.require(Address.isContract(account));
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
  function internalReconcileWithInsurer(ICoverageDistributor insurer, bool updateRate)
    internal
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
      DemandedCoverage memory coverage
    )
  {
    Balances.RateAccWithUint16 memory b = _syncBalance(address(insurer));
    _ensureHolder(b.extra);

    (receivedCoverage, receivedCollateral, coverage) = insurer.receiveDemandedCoverage(address(this), 0);
    // console.log('internalReconcileWithInsurer', address(this), coverage.totalPremium, coverage.premiumRate);
    if (receivedCoverage != 0 || receivedCollateral != 0) {
      internalCoverageReceived(address(insurer), receivedCoverage, receivedCollateral);
    }

    (Balances.RateAcc memory totals, bool updated) = _syncInsurerBalance(b, coverage);

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate || updateRate)) {
      if (!updated) {
        totals = internalSyncTotals();
        updated = true;
      }
      uint88 prevRate = b.rate;
      Arithmetic.require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
      if (prevRate > b.rate) {
        totals.rate -= prevRate - b.rate;
      } else {
        totals.rate += b.rate - prevRate;
      }
    }

    if (updated) {
      _totalAllocatedDemand = totals;
      _balances[address(insurer)] = b;
    }
  }

  function internalCoverageReceived(
    address insurer,
    uint256 receivedCoverage,
    uint256 receivedCollateral
  ) internal virtual;

  function _syncInsurerBalance(Balances.RateAccWithUint16 memory b, DemandedCoverage memory coverage)
    private
    view
    returns (Balances.RateAcc memory totals, bool)
  {
    uint256 diff;
    if (b.accum != coverage.totalPremium) {
      totals = internalSyncTotals();
      if (b.accum < coverage.totalPremium) {
        // technical underpayment
        diff = coverage.totalPremium - b.accum;
        diff += totals.accum;
        Arithmetic.require((totals.accum = uint128(diff)) == diff);
      } else {
        totals.accum -= uint128(diff = b.accum - coverage.totalPremium);
      }

      b.accum = uint120(coverage.totalPremium);
    }

    return (totals, diff != 0);
  }

  /// @dev Do the same as `internalReconcileWithInsurer` but only as a view, don't make changes
  function internalReconcileWithInsurerView(ICoverageDistributor insurer, Balances.RateAcc memory totals)
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

    (receivedCoverage, coverage) = insurer.receivableDemandedCoverage(address(this), 0);
    State.require(b.updatedAt >= coverage.premiumUpdatedAt);

    (totals, ) = _syncInsurerBalance(b, coverage);

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate)) {
      Arithmetic.require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
    }
  }
}
