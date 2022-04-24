// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/Math.sol';

import 'hardhat/console.sol';

library BalancerLib {
  struct TokenBalance {
    uint128 availableAmount;
    uint128 availableValue;
    uint128 totalAmount;
    uint128 saturationAmount;
  }

  struct PoolBalance {
    mapping(address => TokenBalance) balances;
    uint152 totalValue;
    uint104 totalFeeValue;
    uint256 totalBaseValue;
  }

  function addLiquidity(
    PoolBalance storage p,
    address token,
    uint256 value,
    uint256 amount
  ) internal {
    TokenBalance memory b = p.balances[token];

    require((b.totalAmount = uint128(b.totalAmount + amount)) >= amount);
    require((b.availableAmount = uint128(b.availableAmount + amount)) >= amount);
    require((b.availableValue = uint128(b.availableValue + value)) >= value);
    b.saturationAmount = (1 + b.totalAmount) >> 4;

    p.balances[token] = b;
    p.totalBaseValue += value;
  }

  function buyToken(
    PoolBalance storage p,
    address token,
    uint256 maxValue,
    uint256 minAmount
  ) internal returns (uint256 amount) {
    TokenBalance memory b = p.balances[token];
    uint256 tv0 = p.totalValue;
    uint256 fee;

    (amount, fee) = calcAmount(b, p.totalBaseValue, tv0, maxValue, minAmount);

    if (amount > 0) {
      require((p.totalValue = uint152(tv0 + maxValue)) >= maxValue);
      p.balances[token] = b;

      if (fee > 0) {
        // TODO fee value
        // _totalFeeValue = x
      }
    }
  }

  function calcAmount(
    TokenBalance memory b,
    uint256 totalBaseValue,
    uint256 tv0,
    uint256 maxValue,
    uint256 minAmount
  ) internal pure returns (uint256 amount, uint256 fee) {
    uint256 x0;
    uint256 x;

    if (b.availableAmount > b.saturationAmount) {
      // price segment starts at the flat section of the curve

      (x0, x) = _calcFlat(b, totalBaseValue, tv0, maxValue);

      if (x < b.saturationAmount) {
        // TODO x == 0 ?
        // ... and ends at the steep section of the curve
        // so, 2 parts of the segment should be calculated separately

        if ((x0 - x) < minAmount) {
          // shortcut
          return (0, 0);
        }

        fee = x;
        uint128 valueFlat = _calcFlatRev(b, totalBaseValue, tv0, x0 - b.saturationAmount);
        // update state - here
        b.availableAmount = b.saturationAmount;
        b.availableValue += valueFlat;

        (, x) = _calcSteep(b, totalBaseValue, tv0 + valueFlat, maxValue - valueFlat);
        fee = x - fee;
        b.availableValue -= valueFlat;
      }
    } else {
      (x0, x) = _calcSteep(b, totalBaseValue, tv0, maxValue);
    }

    if ((amount = x0 - x) >= minAmount) {
      b.availableAmount = uint128(x);
      b.availableValue += uint128(maxValue);
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
    uint256 y0 = (b.availableValue * totalBaseValue) / tv;
    x = (x0 * y0) / (y0 + dy);
  }

  function _calcSteep(
    TokenBalance memory b,
    uint256 totalBaseValue,
    uint256 tv0,
    uint256 dy
  ) private pure returns (uint256 x0, uint256 x) {
    x0 = (b.totalAmount * b.availableAmount) / b.saturationAmount;
    uint256 tv = tv0 + dy;
    uint256 y0 = (b.availableValue * totalBaseValue) / tv;
    x = (x0 * y0) / (y0 + dy);
  }

  function _calcFlatRev(
    TokenBalance memory u,
    uint256 totalBaseValue,
    uint256 tv0,
    uint256 dx
  ) private pure returns (uint128 dy) {
    uint256 x = u.totalAmount - dx;
    uint256 c = u.availableValue * totalBaseValue * dx;
    uint256 b = tv0;

    dy = uint128((Math.sqrt((b * b) / x + (4 * c) / x) - b) / 2);
  }
}
