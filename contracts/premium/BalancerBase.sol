// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/Math.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IPremiumSource.sol';

import 'hardhat/console.sol';

contract BalancerBase {
  struct TokenBalance {
    uint128 availableAmount;
    uint128 availableValue;
    uint128 totalAmount;
    uint16 saturationPct;
    uint32 lastUpdateAt;
  }

  mapping(address => TokenBalance) private _balances; // [token]
  mapping(address => IPremiumSource) private _sources;

  uint152 private _totalValue;
  uint104 private _totalFeeValue;

  uint256 private _totalBaseValue;

  function addLiquidity(
    address token,
    uint256 value,
    uint256 amount
  ) internal {
    TokenBalance memory b = _balances[token];

    require((b.totalAmount = uint128(b.totalAmount + amount)) >= amount);
    require((b.availableAmount = uint128(b.availableAmount + amount)) >= amount);
    require((b.availableValue = uint128(b.availableValue + value)) >= value);

    _balances[token] = b;
    _totalBaseValue += value;
  }

  function takeLiquidity(
    address token,
    uint256 maxValue,
    uint256 minAmount
  ) internal returns (uint256 amount) {
    TokenBalance memory b = _balances[token];
    uint256 tv0 = _totalValue;
    uint256 fee;

    (amount, fee) = _calcAmount(b, tv0, maxValue, minAmount);

    if (amount > 0) {
      require((_totalValue = uint152(tv0 + maxValue)) >= maxValue);
      _balances[token] = b;

      if (fee > 0) {
        require((_totalFeeValue += uint104(fee)) >= fee);
      }
    }
  }

  function _calcAmount(
    TokenBalance memory b,
    uint256 tv0,
    uint256 maxValue,
    uint256 minAmount
  ) internal view returns (uint256 amount, uint256 fee) {
    uint256 x0;
    uint256 x;

    uint256 saturationAmount = PercentageMath.percentMul(b.totalAmount, b.saturationPct);

    if (b.availableAmount > saturationAmount) {
      // price segment starts at the flat section of the curve

      (x0, x) = _calcFlat(b, tv0, maxValue);

      if (x < saturationAmount) {
        // TODO _pullSource(b); // updates totalVelue and saturation amount

        // TODO x == 0 ?
        // ... and ends at the steep section of the curve
        // so, 2 parts of the segment should be calculated separately

        if ((x0 - x) < minAmount) {
          // shortcut
          return (0, 0);
        }

        fee = x;
        uint128 valueFlat = _calcFlatRev(b, tv0, x0 - saturationAmount);
        // update state - here
        b.availableAmount = uint128(saturationAmount);
        b.availableValue += valueFlat;

        (, x) = _calcSteep(b, tv0 + valueFlat, maxValue - valueFlat, saturationAmount);
        fee = x - fee;
        b.availableValue -= valueFlat;
      }
    } else {
      // TODO _pullSource(b);
      (x0, x) = _calcSteep(b, tv0, maxValue, saturationAmount);
    }

    if ((amount = x0 - x) >= minAmount) {
      b.availableAmount = uint128(x);
      b.availableValue -= uint128(maxValue);
    } else {
      amount = 0;
    }
  }

  function _calcFlat(
    TokenBalance memory b,
    uint256 tv0,
    uint256 dy
  ) private view returns (uint256 x0, uint256 x) {
    x0 = b.totalAmount;
    uint256 tv = tv0 + dy;
    uint256 y0 = (b.availableValue * _totalBaseValue) / tv;
    x = (x0 * y0) / (y0 + dy);
  }

  function _calcSteep(
    TokenBalance memory b,
    uint256 tv0,
    uint256 dy,
    uint256 saturationAmount
  ) private view returns (uint256 x0, uint256 x) {
    x0 = (b.totalAmount * b.availableAmount) / saturationAmount;
    uint256 tv = tv0 + dy;
    uint256 y0 = (b.availableValue * _totalBaseValue) / tv;
    x = (x0 * y0) / (y0 + dy);
  }

  function _calcFlatRev(
    TokenBalance memory u,
    uint256 tv0,
    uint256 dx
  ) private view returns (uint128 dy) {
    uint256 x = u.totalAmount - dx;
    uint256 c = u.availableValue * _totalBaseValue * dx;
    uint256 b = tv0;

    dy = uint128((Math.sqrt((b * b) / x + (4 * c) / x) - b) / 2);
  }
}
