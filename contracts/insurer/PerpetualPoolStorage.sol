// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import './WeightedPoolStorage.sol';

abstract contract PerpetualPoolStorage is WeightedPoolStorage, ERC20BalancelessBase {
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;

  mapping(address => uint256) internal _premiums;

  Balances.RateAcc private _totalRate;

  /// @dev Performed before balance updates. The total rate accum by the pool is updated, and then the user balance is updated
  function _beforeAnyBalanceUpdate() internal view returns (Balances.RateAcc memory totals) {
    totals = _totalRate.sync(uint32(block.timestamp));
  }

  /// @dev Performed before balance updates. The total rate accum by the pool is updated, and then the user balance is updated
  function _beforeBalanceUpdate(address account) internal returns (UserBalance memory b, Balances.RateAcc memory totals) {
    totals = _beforeAnyBalanceUpdate();
    b = _syncBalance(account, totals);
  }

  /// @dev Updates _premiums with total premium earned by user. Each user's balance is marked by the amount
  ///  of premium collected by the pool at time of update
  function _syncBalance(address account, Balances.RateAcc memory totals) internal returns (UserBalance memory b) {
    b = _balances[account];
    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.extra;
      if (premiumDiff > 0) {
        _premiums[account] += premiumDiff.rayMul(b.balance);
      }
    }
    b.extra = totals.accum;
  }

  /// @dev After the balance of the pool is updated, update the _totalRate
  function _afterBalanceUpdate(
    uint256 newExcess,
    Balances.RateAcc memory totals,
    DemandedCoverage memory coverage
  ) internal returns (Balances.RateAcc memory) {
    // console.log('_afterBalanceUpdate', coverage.premiumRate, newExcess, coverage.totalCovered + coverage.pendingCovered);

    uint256 rate = coverage.premiumRate == 0 ? 0 : uint256(coverage.premiumRate).rayDiv(newExcess + coverage.totalCovered + coverage.pendingCovered);
    // earns per second * 10^27
    _totalRate = totals.setRateAfterSync(rate.rayMul(exchangeRate()));
    return totals;
  }
}
