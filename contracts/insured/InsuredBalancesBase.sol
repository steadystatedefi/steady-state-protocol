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

/// @dev A template to track how much premium this insured has to pay to each insurer (both total balance and rate).
/// @dev The premium balances and rates are calculated as streaming and denominated in CC-value.
/// @dev Also rates here are based on the *requested* demand, not on provided coverage (which is less).
/// @dev This ensures that prepayment will always be sufficient, but it is excessive.
/// @dev To correct (release) the excessive prepayment by actual coverage, reconciliation should be done.
/// @dev This contract is an ERC20 and a balance represents a RATE (i.e. a holder of 10 tokens will accumulate premium at rate of 10 CC per second).
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

  /// @dev Mints to the account (insurer) tokens equivalent to the premium rate this insured has to pay based on demanded coverage.
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

  /// @dev NB! This doesnt transfer an accumulated premium value, only a premium rate.
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

  /// @dev stops streaming of premium values to holder of tokens. Applied on cancellation of insurance.
  function internalCancelRates() internal {
    State.require(_cancelledAt == 0);
    _cancelledAt = uint32(block.timestamp);
  }

  function _syncTimestamp() private view returns (uint32) {
    uint32 ts = _cancelledAt;
    return ts > 0 ? ts : uint32(block.timestamp);
  }

  /// @return total rate and balance adjusted by the given timestamp `at`
  function internalExpectedTotals(uint32 at) internal view returns (Balances.RateAcc memory) {
    Value.require(at >= block.timestamp);
    uint32 ts = _cancelledAt;
    return _totalAllocatedDemand.sync(ts > 0 && ts <= at ? ts : at);
  }

  /// @return total rate and balance adjusted by the current timestamp
  function internalSyncTotals() internal view returns (Balances.RateAcc memory) {
    return _totalAllocatedDemand.sync(_syncTimestamp());
  }

  /// @return total rate and balance of the account adjusted by the current timestamp
  function _syncBalance(address account) private view returns (Balances.RateAccWithUint16 memory) {
    return _balances[account].sync(_syncTimestamp());
  }

  /// @return premium rate allocated to this account
  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].rate;
  }

  /// @return rate (premium) allocated to this account
  /// @return premium value accumulated by this account, this value may be reduced after reconciliation(s)
  function balancesOf(address account) public view returns (uint256 rate, uint256 premium) {
    Balances.RateAccWithUint16 memory b = _syncBalance(account);
    return (b.rate, b.accum);
  }

  /// @return total premium rate of this insured based on demanded coverage
  function totalSupply() public view override returns (uint256) {
    return _totalAllocatedDemand.rate;
  }

  /// @return rate is total premium rate of this insured based on demanded coverage
  /// @return accumulated is total amount of premium to be pre-paid by the policy. It can be reduced after reconciliation(s)
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

  /// @dev Reconciles the amount of pre-paid premium value and actual premium value requested by the insurer
  /// @param insurer to reconcile with
  /// @param updateRate is true to always adjust rate, otherwise rate will only be update when it is higher on insurer's side.
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

  /// @dev Do the same as `internalReconcileWithInsurer` but only as a view with no state changes
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

  function totalReceivedCollateral() public view returns (uint256 u) {
    (, , u) = ISubBalance(collateral()).balancesOf(address(this));
  }
}
