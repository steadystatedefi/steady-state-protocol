// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/WadRayMath.sol';
import './InvestmentCurrencyBase.sol';

abstract contract YieldingBase {
  using Math for uint256;
  using WadRayMath for uint256;
  using InvestAccount for InvestAccount.Balance;

  struct YieldBalance {
    uint128 lastRateAccum;
    uint128 yieldAccum;
  }

  mapping(address => YieldBalance) private _yields; // [account]
  uint128 private _yieldRateAccum; // wad-based

  uint32 private _lastYieldAt;
  uint96 private _lastIndicativeRate;

  function internalBeforeManagedBalanceUpdate(address account, InvestAccount.Balance accBalance) internal virtual {
    _updateYieldBalance(account, accBalance, 0);
  }

  function _updateYieldBalance(
    address account,
    InvestAccount.Balance accBalance,
    uint256 deduct
  ) private returns (uint256) {
    uint256 v = accBalance.isNotManagedBalance() ? 0 : accBalance.ownBalance() + accBalance.givenBalance();
    YieldBalance storage yield = _yields[account];

    uint128 yieldRateAccum;
    if (v != 0) {
      yieldRateAccum = _yieldRateAccum;
      v = v.wadMul(Math.boundedSub128(yieldRateAccum, yield.lastRateAccum));
    }

    if (v != 0 || deduct != 0) {
      yield.lastRateAccum = yieldRateAccum;
      uint128 yieldAccum = yield.yieldAccum;
      Arithmetic.require((yieldAccum += uint128(v)) >= v);
      (yield.yieldAccum, deduct) = Math.boundedMaxSub128(yieldAccum, deduct);
    }
    return deduct;
  }

  function totalAndManagedSupply() public view virtual returns (uint256, uint256);

  function internalGetBalance(address account) internal view virtual returns (InvestAccount.Balance);

  function internalAddYield(uint256 amount) internal {
    (, uint256 totalManaged) = totalAndManagedSupply();
    amount = amount.wadDiv(totalManaged);

    uint128 prevYieldRateAccum = _yieldRateAccum;
    uint128 yieldRateAccum = prevYieldRateAccum + uint128(amount);
    Arithmetic.require(yieldRateAccum >= amount);
    _yieldRateAccum = yieldRateAccum;

    internalUpdateYieldRate(prevYieldRateAccum, yieldRateAccum);
  }

  function internalPullYield(address account) internal returns (uint256) {
    InvestAccount.Balance accBalance = internalGetBalance(account);
    return _updateYieldBalance(account, accBalance, type(uint256).max);
  }

  function internalUpdateYieldRate(uint256 prevYieldRateAccum, uint256 yieldRateAccum) internal virtual {
    uint256 v = _lastYieldAt;
    if (v != 0) {
      v -= block.timestamp;
      if (v == 0) {
        return;
      }
      v = yieldRateAccum.boundedSub(prevYieldRateAccum).divUp(v);
      _lastIndicativeRate = v >= type(uint96).max ? type(uint96).max : uint96(v);
    }
    _lastYieldAt = uint32(block.timestamp);
  }

  function indicativeYieldRate() internal view returns (uint256, uint32) {
    return (_lastIndicativeRate, _lastYieldAt);
  }
}
