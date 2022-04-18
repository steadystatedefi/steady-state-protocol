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

/// @dev Calculates retroactive premium paid by Insured to Insurer over-time.
/// @dev Insured pool tokens = investment * premium rate (e.g $1000 @ 5% premium = 50 tokens)
abstract contract InsuredBalancesBase is InsurancePoolBase, ERC20BalancelessBase, IInsuredEvents, IPremiumCalculator {
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

  ///@dev Mint the correct amount of tokens for the account (investor)
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

  function internalCancelRates() internal {
    require(_cancelledAt == 0);
    _cancelledAt = uint32(block.timestamp);
  }

  function _syncTimestamp() private view returns (uint32) {
    uint32 ts = _cancelledAt;
    return ts > 0 ? ts : uint32(block.timestamp);
  }

  function internalSyncTotals() internal view returns (Balances.RateAcc memory) {
    return _totals.sync(_syncTimestamp());
  }

  function _syncBalance(address account) private view returns (Balances.RateAccWithUint16 memory b) {
    return _balances[account].sync(_syncTimestamp());
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].rate;
  }

  function balancesOf(address account) public view returns (uint256 rate, uint256 premium) {
    Balances.RateAccWithUint16 memory b = _syncBalance(account);
    return (b.rate, b.accum);
  }

  function totalSupply() public view override returns (uint256) {
    return _totals.rate;
  }

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

  ///@dev Reconcile the amount of collected premium and current premium rate with the Insurer
  ///@param updateRate whether the total rate of this Insured pool should be updated
  function internalReconcileWithInsurer(IInsurerPoolDemand insurer, bool updateRate)
    internal
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    Balances.RateAccWithUint16 memory b = _syncBalance(address(insurer));
    _ensureHolder(b.extra);

    (receivedCoverage, coverage) = insurer.receiveDemandedCoverage(address(this));
    // console.log('internalReconcileWithInsurer', address(this), coverage.totalPremium, coverage.premiumRate);

    (Balances.RateAcc memory totals, bool updated) = _syncInsurerBalance(b, coverage);

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate || updateRate)) {
      if (!updated) {
        totals = internalSyncTotals();
        updated = true;
      }
      uint88 prevRate = b.rate;
      require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
      if (prevRate > b.rate) {
        totals.rate -= prevRate - b.rate;
      } else {
        totals.rate += b.rate - prevRate;
      }
    }

    if (updated) {
      _totals = totals;
      _balances[address(insurer)] = b;
    }
  }

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
        require((totals.accum = uint128(diff)) == diff);
        revert('technical underpayment'); // TODO this should not happen now, but remove it later
      } else {
        totals.accum -= uint128(diff = b.accum - coverage.totalPremium); // TODO (Tyler)
      }

      b.accum = uint120(coverage.totalPremium);
    }

    return (totals, diff != 0);
  }

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

    (totals, ) = _syncInsurerBalance(b, coverage);

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate)) {
      require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
    }
  }
}
