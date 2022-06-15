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
    c.sA = (uint256(balance.rate) * config.n).wadDiv(c.vA = config.price);
    c.w = config.w;

    uint256 k = _calcScale(balance, total);
    amount = balance.accum - _calcA(c, balance.accum, value.rayMul(k));

    if (amount >= minAmount && amount > 0) {
      require((balance.accum = uint128(balance.accum - amount)) > 0);
      total.accum = uint128(total.accum - amount);

      fee = amount.wadMul(c.vA);
      if (fee < value) {
        fee = value - fee;

        // TODO this is a rough supremum of value's part that should be reserved for discounting of less popular assets
        // an exact formula requires log()
        k = (k + _calcScale(balance, total)) >> 1;
        // swap with bonus relies on the assets with liquidity penalty
        k = k < WadRayMath.RAY ? value - value.rayMul(k) : 0;

        // TODO When the constant-product formula (1/x) will produce less fees than required by scaling (integral(1/x))?
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
    return uint256(balance.accum).rayDiv(total.accum).rayDiv(uint256(balance.rate).rayDiv(total.rate));
  }

  struct AssetConfig {
    uint160 price; // target price, wad-multiplier, uint192
    uint64 w; // [0..1] controls fees, uint64
    uint32 n; // n mint-seconds for the saturation point
  }

  struct CPConfig {
    uint256 sA; // amount of an asset at saturation
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
      } else {
        a1 = _calcCurve(c, a, dV);
      }
    } else {
      a1 = _calcSat(c, a, dV);
    }
  }

  function _calcCurve(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    uint256 cA = a.wadDiv(c.w);
    uint256 cV = cA.wadMul(c.vA);

    a1 = _calc(cA, dV, cA, cV);
    if (a1 < c.sA) {
      uint256 v1 = (cA * cV) / (cA - (a - c.sA));
      uint256 sdV = v1 - cV;

      if (a != cA) {
        cA = _calc(cA, sdV, cA, cV); // requied when weight is applied to A
      }
      a1 = _calc(c.sA, dV - sdV, cA, v1);
    }
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
      a1 = _calcSat(c, c.sA, dV - (a - c.sA).wadMul(c.vA));
    }
  }

  function _calcSat(
    CPConfig memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    uint256 cA = c.sA;
    uint256 cV = cA.wadMul(c.vA);

    a1 = _calc(a, dV, cA, cV);
  }

  function _calc(
    uint256 a,
    uint256 dV,
    uint256 cA,
    uint256 cV
  ) private pure returns (uint256) {
    // NB! RAY*RAY base applied here to increase precision for the inversed math
    return WadRayMath.RAY.rayDiv(WadRayMath.RAY.rayDiv(a) + dV.rayDiv(cV).rayDiv(cA));
  }
}
