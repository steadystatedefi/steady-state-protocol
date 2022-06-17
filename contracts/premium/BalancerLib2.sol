// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IPremiumSource.sol';
import '../interfaces/IPremiumBalanceHolder.sol';
import '../libraries/Balances.sol';

import 'hardhat/console.sol';

library BalancerLib2 {
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;

  struct PoolBalances {
    mapping(address => Balances.RateAcc) balances;
    Balances.RateAcc totalBalance;
    mapping(address => AssetConfig) configs;
    uint160 spConst;
    uint32 spFactor;
  }

  function swapToken(
    PoolBalances storage p,
    address token,
    uint256 value,
    uint256 minAmount
  ) internal returns (uint256 amount, uint256 fee) {
    Balances.RateAcc memory balance = p.balances[token].sync(uint32(block.timestamp));
    Balances.RateAcc memory total = p.totalBalance.sync(uint32(block.timestamp));

    AssetConfig storage config = p.configs[token];

    CPConfig memory c;
    c.w = config.w;
    c.vA = config.price;

    {
      StarvationPointMode spMode = config.spMode;
      if (spMode <= StarvationPointMode.GlobalRateFactor) {
        c.sA = (uint256(balance.rate) * (spMode == StarvationPointMode.RateFactor ? config.n : p.spFactor)).wadDiv(c.vA);
      } else {
        c.sA = spMode == StarvationPointMode.Constant ? config.spConst : p.spConst;
      }
    }

    uint256 k = _calcScale(balance, total);
    amount = _calcA(c, balance.accum, value.rayMul(k));

    if (amount == 0 && c.sA != 0 && balance.accum > 0) {
      amount = 1;
    }
    amount = balance.accum - amount;

    if (amount >= minAmount && amount > 0) {
      balance.accum = uint128(balance.accum - amount);
      total.accum = uint128(total.accum - amount);

      if ((fee = amount.wadMul(c.vA)) < value) {
        // This is a total amount of fees - it has 2 parts: balancing levy and volume penalty.
        fee = value - fee;
        // The balancing levy can be positive (for popular assets) or negative (for non-popular assets) and is distributed within the balancer.
        // The volume penalty is charged on large transactions and can be taken out.

        // This formula is an aproximation that overestimates the levy and underpays the penalty. It is an acceptable behavior.
        // More accurate formula needs log() which may be an overkill for this case.
        k = (k + _calcScale(balance, total)) >> 1;
        // The negative levy is ignored here as it was applied with rayMul(k) above.
        k = k < WadRayMath.RAY ? value - value.rayMul(WadRayMath.RAY - k) : 0;

        // The constant-product formula (1/x) should produce enough fees than required by balancing levy ... but there can be gaps.
        fee = fee > k ? fee - k : 0;
      } else {
        // got more with the bonus
        fee = 0;
      }

      p.balances[token] = balance;
      p.totalBalance = total;
    } else {
      amount = 0;
    }
  }

  function _calcScale(Balances.RateAcc memory balance, Balances.RateAcc memory total) private pure returns (uint256) {
    return
      total.accum == 0 || balance.rate == 0
        ? WadRayMath.RAY
        : (uint256(balance.accum).rayDiv(total.accum) * total.rate + (balance.rate >> 1)) / uint256(balance.rate);
  }

  enum StarvationPointMode {
    RateFactor,
    GlobalRateFactor,
    Constant,
    GlobalConstant
  }

  struct AssetConfig {
    uint152 price; // target price, wad-multiplier, uint192
    uint64 w; // [0..1] fee control, uint64
    uint32 n; // n mint-seconds for the starvation point
    StarvationPointMode spMode;
    uint256 spConst;
  }

  struct CPConfig {
    uint256 sA; // amount of an asset at starvation
    uint256 vA; // target price, wad-multiplier, uint192
    uint256 w; // [0..1] controls fees, uint64
  }

  function _calcA(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    if (a > c.sA) {
      if (c.w == 0) {
        // no fee based on amount
        a1 = _calcFlat(c, a, dV);
      } else if (c.w == WadRayMath.WAD) {
        a1 = _calcCurve(c, a, dV);
      } else {
        a1 = _calcCurveW(c, a, dV);
      }
    } else {
      a1 = _calcSat(c, a, dV);
    }
  }

  function _calcCurve(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256) {
    return _calc(a, dV, a, a.wadMul(c.vA));
  }

  function _calcCurveW(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    uint256 wA = a.wadDiv(c.w);
    uint256 wV = wA.wadMul(c.vA);

    a1 = _calc(wA, dV, wA, wV);

    uint256 wsA = wA - (a - c.sA);
    if (a1 < wsA) {
      uint256 wsV = (wA * wV) / wsA;
      return _calc(c.sA, dV - (wsV - wV), c.sA, wsV);
    }

    return a - (wA - a1);
  }

  function _calcFlat(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    uint256 dA = dV.wadDiv(c.vA);
    if (c.sA + dA <= a) {
      a1 = a - dA;
    } else {
      dV -= (a - c.sA).wadMul(c.vA);
      a1 = _calcSat(c, c.sA, dV);
    }
  }

  function _calcSat(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    a1 = _calc(a, dV, c.sA, c.sA.wadMul(c.vA));
  }

  function _calc(
    uint256 a,
    uint256 dV,
    uint256 cA,
    uint256 cV
  ) private pure returns (uint256) {
    if (cV > cA) {
      (cA, cV) = (cV, cA);
    }
    cV = cV * WadRayMath.RAY;

    return Math.mulDiv(cV, cA, dV * WadRayMath.RAY + Math.mulDiv(cV, cA, a));
  }
}
