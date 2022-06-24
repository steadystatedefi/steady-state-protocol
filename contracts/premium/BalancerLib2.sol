// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';

import 'hardhat/console.sol';

library BalancerLib2 {
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;

  struct AssetBalance {
    uint128 accum;
    uint96 rate;
    // uint32
  }

  struct AssetBalancer {
    mapping(address => AssetBalance) balances; // [token] total balance and rate of all sources using this token
    Balances.RateAcc totalBalance; // total balance and rate of all sources
    mapping(address => AssetConfig) configs; // [token] token balancing configuration
    uint160 spConst; // value for (BF_SPM_GLOBAL | BF_SPM_CONSTANT) starvation point mode
    uint32 spFactor; // value for (BF_SPM_GLOBAL | !BF_SPM_CONSTANT) starvation point mode
  }

  struct AssetConfig {
    uint152 price; // target price, wad-multiplier, uint192
    uint64 w; // [0..1] fee control, uint64
    uint32 n; // n mint-seconds for the starvation point, // value for (!BF_SPM_GLOBAL | !BF_SPM_CONSTANT) starvation point mode
    uint16 flags; // starvation point modes and asset states
    uint160 spConst; // value for (!BF_SPM_GLOBAL | BF_SPM_CONSTANT) starvation point mode
  }

  uint8 private constant FINISHED_OFFSET = 8;

  uint16 internal constant BF_SPM_MASK = 3;
  uint16 internal constant BF_SPM_F_MASK = BF_SPM_MASK << FINISHED_OFFSET;

  uint16 internal constant BF_SPM_GLOBAL = 1 << 0;
  uint16 internal constant BF_SPM_CONSTANT = 1 << 1;

  uint16 internal constant BF_AUTO_REPLENISH = 1 << 6; // pull a source at every swap
  uint16 internal constant BF_FINISHED = 1 << 7; // no more sources for this token

  uint16 internal constant BF_SPM_F_GLOBAL = BF_SPM_GLOBAL << FINISHED_OFFSET;
  uint16 internal constant BF_SPM_F_CONSTANT = BF_SPM_CONSTANT << FINISHED_OFFSET;

  uint16 internal constant BF_SUSPENDED = 1 << 15; // token is suspended

  struct CalcParams {
    uint256 sA; // amount of an asset at starvation
    uint256 vA; // target price, wad-multiplier, uint192
    uint256 w; // [0..1] wad, controls fees, uint64
    uint256 extraTotal;
  }

  struct ReplenishParams {
    address actuary;
    address source;
    address token;
    function(
      ReplenishParams memory,
      uint256 /* requestedAmount */
    )
      returns (
        uint256, /* replenishedAmount */
        uint256, /* replenishedValue */
        uint256 /* expectedAmount */
      ) replenishFn;
  }

  function swapExternalAsset(
    AssetBalancer storage p,
    address token,
    uint256 value,
    uint256 minAmount,
    uint256 assetBalance
  ) internal view returns (uint256 amount, uint256 fee) {
    return swapExternalAssetInBatch(p, token, value, minAmount, assetBalance, p.totalBalance);
  }

  function swapExternalAssetInBatch(
    AssetBalancer storage p,
    address token,
    uint256 value,
    uint256 minAmount,
    uint256 assetBalance,
    Balances.RateAcc memory total
  ) internal view returns (uint256 amount, uint256 fee) {
    AssetBalance memory balance;
    total.sync(uint32(block.timestamp));
    (CalcParams memory c, ) = _calcParams(p, token, balance.rate, true);

    require((total.accum += uint128(assetBalance)) >= assetBalance);
    balance.accum = uint128(assetBalance);

    (amount, fee) = _swapAsset(value, minAmount, c, balance, total);
  }

  function swapAsset(
    AssetBalancer storage p,
    ReplenishParams memory params,
    uint256 value,
    uint256 minAmount,
    uint256 extraTotal
  ) internal returns (uint256 amount, uint256 fee) {
    Balances.RateAcc memory total = p.totalBalance;
    bool updateTotal;
    (amount, fee, updateTotal) = swapAssetInBatch(p, params, value, minAmount, extraTotal, total);

    if (updateTotal) {
      p.totalBalance = total;
    }
  }

  function swapAssetInBatch(
    AssetBalancer storage p,
    ReplenishParams memory params,
    uint256 value,
    uint256 minAmount,
    uint256 extraTotal,
    Balances.RateAcc memory total
  )
    internal
    returns (
      uint256 amount,
      uint256 fee,
      bool updateTotal
    )
  {
    AssetBalance memory balance = p.balances[params.token];
    total.sync(uint32(block.timestamp));

    (CalcParams memory c, uint256 flags) = _calcParams(p, params.token, balance.rate, true);

    if (flags & BF_AUTO_REPLENISH != 0 || (balance.rate > 0 && balance.accum <= c.sA)) {
      // c.extraTotal = 0; - it is and it should be zero here
      _replenishAsset(p, params, c, balance, total);
      updateTotal = true;
    }

    c.extraTotal = extraTotal;
    (amount, fee) = _swapAsset(value, minAmount, c, balance, total);
    if (amount > 0) {
      p.balances[params.token] = balance;
      updateTotal = true;
    }
  }

  function _calcParams(
    AssetBalancer storage p,
    address token,
    uint256 rate,
    bool checkSuspended
  ) private view returns (CalcParams memory c, uint256 flags) {
    AssetConfig storage config = p.configs[token];

    c.w = config.w;
    c.vA = config.price;

    {
      flags = config.flags;
      if (flags & BF_SUSPENDED != 0 && checkSuspended) {
        revert Errors.OperationPaused();
      }
      if (flags & BF_FINISHED != 0) {
        flags <<= FINISHED_OFFSET;
      }

      if (flags & BF_SPM_CONSTANT == 0) {
        c.sA = (rate * (flags & BF_SPM_GLOBAL == 0 ? config.n : p.spFactor)).wadDiv(c.vA);
      } else {
        c.sA = flags & BF_SPM_GLOBAL == 0 ? config.spConst : p.spConst;
      }
    }
  }

  function _swapAsset(
    uint256 value,
    uint256 minAmount,
    CalcParams memory c,
    AssetBalance memory balance,
    Balances.RateAcc memory total
  ) private pure returns (uint256 amount, uint256 fee) {
    uint256 k = _calcScale(balance, total, c.extraTotal);
    amount = _calcAmount(c, balance.accum, value.rayMul(k));

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
        k = (k + _calcScale(balance, total, c.extraTotal)) >> 1;
        // The negative levy is ignored here as it was applied with rayMul(k) above.
        k = k < WadRayMath.RAY ? value - value.rayMul(WadRayMath.RAY - k) : 0;

        // The constant-product formula (1/x) should produce enough fees than required by balancing levy ... but there can be gaps.
        fee = fee > k ? fee - k : 0;
      } else {
        // got more with the bonus
        fee = 0;
      }
    } else {
      amount = 0;
    }
  }

  function _calcScale(
    AssetBalance memory balance,
    Balances.RateAcc memory total,
    uint256 extraTotal
  ) private pure returns (uint256) {
    return
      total.accum == 0 || balance.rate == 0
        ? WadRayMath.RAY
        : (uint256(balance.accum).rayDiv(total.accum + extraTotal) * total.rate + (balance.rate >> 1)) / uint256(balance.rate);
  }

  function _calcAmount(
    CalcParams memory c,
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
      a1 = _calcStarvation(c, a, dV);
    }
  }

  function _calcCurve(
    CalcParams memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256) {
    return _calc(a, dV, a, a.wadMul(c.vA));
  }

  function _calcCurveW(
    CalcParams memory c,
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
    CalcParams memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    uint256 dA = dV.wadDiv(c.vA);
    if (c.sA + dA <= a) {
      a1 = a - dA;
    } else {
      dV -= (a - c.sA).wadMul(c.vA);
      a1 = _calcStarvation(c, c.sA, dV);
    }
  }

  function _calcStarvation(
    CalcParams memory c,
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

  function replenishAsset(
    AssetBalancer storage p,
    ReplenishParams memory params,
    uint256 incrementAmount,
    uint96 newRate,
    uint96 lastRate,
    bool checkSuspended
  ) internal returns (bool fully) {
    Balances.RateAcc memory total = _syncTotalBalance(p);
    AssetBalance memory balance = p.balances[params.token];
    (CalcParams memory c, ) = _calcParams(p, params.token, balance.rate, checkSuspended);
    c.extraTotal = incrementAmount;

    if (_replenishAsset(p, params, c, balance, total) < incrementAmount) {
      newRate = 0;
    } else {
      fully = true;
    }

    if (lastRate != newRate) {
      _changeRate(lastRate, newRate, balance, total);
    }

    _save(p, params, balance, total);
  }

  function _syncTotalBalance(AssetBalancer storage p) private view returns (Balances.RateAcc memory) {
    return p.totalBalance.sync(uint32(block.timestamp));
  }

  function _save(
    AssetBalancer storage p,
    address token,
    AssetBalance memory balance,
    Balances.RateAcc memory total
  ) private {
    p.balances[token] = balance;
    p.totalBalance = total;
  }

  function _save(
    AssetBalancer storage p,
    ReplenishParams memory params,
    AssetBalance memory balance,
    Balances.RateAcc memory total
  ) private {
    _save(p, params.token, balance, total);
  }

  function _changeRate(
    uint96 lastRate,
    uint96 newRate,
    AssetBalance memory balance,
    Balances.RateAcc memory total
  ) private pure {
    if (newRate > lastRate) {
      unchecked {
        newRate = newRate - lastRate;
      }
      require((balance.rate += newRate) >= newRate);
      total.rate += newRate;
    } else {
      unchecked {
        newRate = lastRate - newRate;
      }
      balance.rate -= newRate;
      total.rate -= newRate;
    }
  }

  function _replenishAsset(
    AssetBalancer storage p,
    ReplenishParams memory params,
    CalcParams memory c,
    AssetBalance memory assetBalance,
    Balances.RateAcc memory total
  ) private returns (uint128) {
    require(total.updatedAt == block.timestamp);

    (uint256 receivedAmount, uint256 v, uint256 expectedAmount) = params.replenishFn(params, c.extraTotal);
    if (receivedAmount == 0 && expectedAmount == 0) {
      return 0;
    }
    require(receivedAmount <= type(uint128).max);

    v = v * WadRayMath.WAD + uint256(assetBalance.accum) * c.vA;
    {
      total.accum = uint128((total.accum - expectedAmount) + receivedAmount);
      assetBalance.accum += uint128(receivedAmount);
    }
    v = v.divUp(assetBalance.accum);

    if (v != c.vA) {
      require((c.vA = p.configs[params.token].price = uint152(v)) == v);
    }

    return uint128(receivedAmount);
  }

  function decRate(
    AssetBalancer storage p,
    address targetToken,
    uint96 lastRate
  ) internal returns (uint96 rate) {
    Balances.RateAcc memory total = _syncTotalBalance(p);
    AssetBalance storage balance = p.balances[targetToken];

    total.rate -= lastRate;
    p.totalBalance = total;

    return (balance.rate -= lastRate);
  }
}
