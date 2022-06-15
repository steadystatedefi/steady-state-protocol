// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/Math.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IPremiumSource.sol';
import '../interfaces/IPremiumBalanceHolder.sol';

import 'hardhat/console.sol';

library BalancerLib {
  struct TokenBalance {
    uint128 cpAmount;
    uint128 cpValue;
    uint128 totalAmount;
    uint16 saturationPct;
    uint32 lastUpdateAt;
  }

  struct PoolPremiums {
    mapping(address => TokenBalance) balances;
    mapping(address => IPremiumSource) sources;
    PoolTotals total;
  }

  struct PoolTotals {
    uint128 value;
    uint128 baseValue;
  }

  function addLiquidity(
    PoolPremiums storage p,
    address token,
    uint256 value,
    uint256 amount
  ) internal {
    TokenBalance memory b = p.balances[token];
    _addLiquidity(b, value, amount);

    p.balances[token] = b;
    require((p.total.baseValue += uint128(value)) >= value);
  }

  function _addLiquidity(
    TokenBalance memory b,
    uint256 value,
    uint256 amount
  ) private view {
    require((b.totalAmount = uint128(b.totalAmount + amount)) >= amount);
    require((b.cpAmount = uint128(b.cpAmount + amount)) >= amount);
    require((b.cpValue = uint128(b.cpValue + value)) >= value);

    if (b.lastUpdateAt > 0) {
      b.lastUpdateAt = uint32(block.timestamp);
    }
  }

  function swapToken(
    PoolPremiums storage p,
    address insurer,
    address token,
    uint256 value,
    uint256 minAmount
  ) internal returns (uint256, uint256) {
    TokenBalance memory b = p.balances[token];
    PoolTotals memory t = p.total;

    (uint256 amount, uint256 fee, uint256 refill) = getAmount(t, b, value, minAmount);

    if (refill > 0) {
      b.lastUpdateAt = uint32(block.timestamp);

      IPremiumSource s = p.sources[token];
      if (address(s) != address(0)) {
        (refill, amount) = s.pullPremiumSource(insurer, refill);
        if (amount > 0) {
          _addLiquidity(b, refill, amount);
          require((t.baseValue += uint128(refill)) >= refill);
          refill = 1;
        }
      }
      (amount, fee, ) = getAmount(t, b, value, minAmount);
    }

    if (amount > 0 || refill > 0) {
      p.balances[token] = b;
    }

    if (amount > 0) {
      require((t.value += uint128(value)) >= value);
    }

    return (amount, fee);
  }

  function _swapToken(
    address insurer,
    TokenBalance memory b,
    PoolTotals memory t,
    mapping(address => IPremiumSource) storage sources,
    address token,
    uint256 value,
    uint256 minAmount
  ) internal returns (uint256, uint256) {
    (uint256 amount, uint256 fee, uint256 refill) = getAmount(t, b, value, minAmount);

    if (refill > 0) {
      b.lastUpdateAt = uint32(block.timestamp);

      IPremiumSource s = sources[token];
      if (address(s) != address(0)) {
        (refill, amount) = s.pullPremiumSource(insurer, refill);
        if (amount > 0) {
          // transfer from or check balance ...
          _addLiquidity(b, refill, amount);
          require((t.baseValue += uint128(refill)) >= refill);
        }
      }
      (amount, fee, ) = getAmount(t, b, value, minAmount);
    }

    return (amount, fee);
  }

  function burnPremium(
    address insurer,
    address account,
    uint256 collateralValue,
    address collateralRecipient
  ) internal {
    IPremiumBalanceHolder(insurer).burnPremium(account, collateralValue, collateralRecipient);
  }

  function getAmount(
    PoolTotals memory total,
    TokenBalance memory b,
    uint256 maxValue,
    uint256 minAmount
  )
    internal
    view
    returns (
      uint256 amount,
      uint256 fee,
      uint256 expectedRefill
    )
  {
    uint256 x0;
    uint256 x;

    uint256 saturationAmount = PercentageMath.percentMul(b.totalAmount, b.saturationPct);

    if (b.cpAmount > saturationAmount) {
      // price segment starts at the flat section of the curve

      (x0, x) = _calcFlat(b, total.baseValue, total.value, maxValue);

      if (x < saturationAmount) {
        if (b.lastUpdateAt > 0 && b.lastUpdateAt < uint32(block.timestamp)) {
          // can be refilled
          x0 -= x;
          return (0, 0, ((saturationAmount - x) * maxValue + (x0 >> 1)) / x0);
        }

        // TODO x == 0 ?
        // ... and ends at the steep section of the curve
        // so, 2 parts of the segment should be calculated separately

        if ((x0 - x) < minAmount) {
          // shortcut
          return (0, 0, 0);
        }

        fee = x;
        uint128 valueFlat = _calcFlatRev(b, total.baseValue, total.value, x0 - saturationAmount);
        // update state - here
        b.cpAmount = uint128(saturationAmount);
        b.cpValue += valueFlat;

        (, x) = _calcSteep(b, total.baseValue, total.value + valueFlat, maxValue - valueFlat, saturationAmount);
        fee = x - fee;
        b.cpValue -= valueFlat;
      }
    } else {
      (x0, x) = _calcSteep(b, total.baseValue, total.value, maxValue, saturationAmount);
    }

    if ((amount = x0 - x) >= minAmount) {
      b.cpAmount = uint128(x);
      b.cpValue += uint128(maxValue); // TODO may be error? should be decrement
    } else {
      amount = 0;
    }
  }

  function _calcFlat(
    TokenBalance memory b,
    uint256 totalBaseValue,
    uint256 tv0,
    uint256 dy
  ) private pure returns (uint256 x0, uint256 x) {
    x0 = b.totalAmount;
    uint256 tv = tv0 + dy;
    uint256 y0 = (b.cpValue * totalBaseValue) / tv;
    x = (x0 * y0) / (y0 + dy);
  }

  function _calcSteep(
    TokenBalance memory b,
    uint256 totalBaseValue,
    uint256 tv0,
    uint256 dy,
    uint256 saturationAmount
  ) private pure returns (uint256 x0, uint256 x) {
    x0 = (b.totalAmount * b.cpAmount) / saturationAmount;
    uint256 tv = tv0 + dy;
    uint256 y0 = (b.cpValue * totalBaseValue) / tv;
    x = (x0 * y0) / (y0 + dy);
  }

  function _calcFlatRev(
    TokenBalance memory u,
    uint256 totalBaseValue,
    uint256 tv0,
    uint256 dx
  ) private pure returns (uint128 dy) {
    uint256 x = u.totalAmount - dx;
    uint256 c = u.cpValue * totalBaseValue * dx;
    uint256 b = tv0;

    dy = uint128((Math.sqrt((b * b) / x + (4 * c) / x) - b) / 2);
  }
}
