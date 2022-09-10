// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';

import 'hardhat/console.sol';

library BalancerLib2 {
  using Math for uint256;
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;

  struct AssetBalance {
    uint128 accumAmount; // amount of asset
    uint96 rateValue; // value per second
    uint32 applyFrom;
  }

  struct AssetBalancer {
    mapping(address => AssetBalance) balances; // [token] total balance and rate of all sources using this token
    Balances.RateAcc totalBalance; // total VALUE balance and VALUE rate of all sources
    mapping(address => AssetConfig) configs; // [token] token balancing configuration
    uint160 spConst; // value, for (BF_SPM_GLOBAL | BF_SPM_CONSTANT) starvation point mode
    uint32 spFactor; // rate multiplier, for (BF_SPM_GLOBAL | !BF_SPM_CONSTANT) starvation point mode
  }

  struct AssetConfig {
    uint144 price; // target price, wad-multiplier
    uint64 w; // [0..1] wad, fee control, uint64
    uint32 n; // rate multiplier, for (!BF_SPM_GLOBAL | !BF_SPM_CONSTANT) starvation point mode
    uint16 flags; // starvation point modes and asset states
    uint160 spConst; // value, for (!BF_SPM_GLOBAL | BF_SPM_CONSTANT) starvation point mode
  }

  uint8 private constant FINISHED_OFFSET = 8;

  uint16 internal constant BF_SPM_GLOBAL = 1 << 0;
  uint16 internal constant BF_SPM_CONSTANT = 1 << 1;
  uint16 internal constant BF_SPM_MAX_WITH_CONST = 1 << 2; // only applicable with BF_SPM_CONSTANT

  uint16 internal constant BF_AUTO_REPLENISH = 1 << 6; // pull a source at every swap
  uint16 internal constant BF_FINISHED = 1 << 7; // no more sources for this token

  uint16 internal constant BF_SPM_MASK = BF_SPM_GLOBAL | BF_SPM_CONSTANT | BF_SPM_MAX_WITH_CONST;
  uint16 internal constant BF_SPM_F_MASK = BF_SPM_MASK << FINISHED_OFFSET;

  // uint16 internal constant BF_SPM_F_GLOBAL = BF_SPM_GLOBAL << FINISHED_OFFSET;
  // uint16 internal constant BF_SPM_F_CONSTANT = BF_SPM_CONSTANT << FINISHED_OFFSET;

  uint32 internal constant SP_EXTERNAL_N_BASE = 1_00_00;

  uint16 internal constant BF_EXTERNAL = 1 << 14;
  uint16 internal constant BF_SUSPENDED = 1 << 15; // token is suspended

  struct CalcParams {
    uint256 sA; // amount of an asset at starvation
    uint256 vA; // target price, wad-multiplier, uint192
    uint256 w; // [0..1] wad, controls fees, uint64
  }

  struct ReplenishParams {
    address actuary;
    address source;
    address token;
    function(
      ReplenishParams memory,
      uint256 /* requestedValue */
    )
      returns (
        uint256, /* replenishedAmount */
        uint256, /* replenishedValue */
        uint256 /*  expectedValue */
      ) replenishFn;
  }

  function swapExternalAsset(
    AssetBalancer storage p,
    address token,
    uint256 value,
    uint256 minAmount,
    uint256 assetAmount,
    uint256 assetFreeAllowance
  ) internal view returns (uint256 amount, uint256 fee) {
    return swapExternalAssetInBatch(p, token, value, minAmount, assetAmount, assetFreeAllowance, p.totalBalance);
  }

  function swapExternalAssetInBatch(
    AssetBalancer storage p,
    address token,
    uint256 value,
    uint256 minAmount,
    uint256 assetAmount,
    uint256 assetLimit,
    Balances.RateAcc memory total
  ) internal view returns (uint256 amount, uint256 fee) {
    total.sync(uint32(block.timestamp));

    Arithmetic.require((total.accum += uint128(assetAmount)) >= assetAmount);

    // amount EQUALS value
    (CalcParams memory c, uint256 flags) = _calcParams(p, assetAmount.boundedSub(assetLimit), true, p.configs[token], WadRayMath.WAD);
    State.require(flags & BF_EXTERNAL != 0);
    // TODO c.sA >>= SP_EXTERNAL_N_SHIFT;

    AssetBalance memory balance;
    balance.accumAmount = uint128(assetAmount);
    // balance.rateValue = 0 suppresses cross-asset balancing
    (amount, fee) = _swapAsset(value, minAmount, c, balance, total);
  }

  function swapAsset(
    AssetBalancer storage p,
    ReplenishParams memory params,
    uint256 value,
    uint256 minAmount
  ) internal returns (uint256 amount, uint256 fee) {
    Balances.RateAcc memory total = p.totalBalance;
    bool updateTotal;
    (amount, fee, updateTotal) = swapAssetInBatch(p, params, value, minAmount, total);

    if (updateTotal) {
      p.totalBalance = total;
    }
  }

  function assetState(AssetBalancer storage p, address token)
    internal
    view
    returns (
      uint256,
      uint256 accum,
      uint256 stravation,
      uint256 price,
      uint256 w
    )
  {
    AssetBalance memory balance = p.balances[token];
    (CalcParams memory c, uint256 flags) = _calcParams(p, token, balance.rateValue, false);
    return (flags, balance.accumAmount, c.sA, c.vA, c.w);
  }

  function swapAssetInBatch(
    AssetBalancer storage p,
    ReplenishParams memory params,
    uint256 value,
    uint256 minAmount,
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

    (CalcParams memory c, uint256 flags) = _calcParams(p, params.token, balance.rateValue, true);

    if (flags & BF_AUTO_REPLENISH != 0 || (balance.rateValue > 0 && balance.accumAmount <= c.sA)) {
      _replenishAsset(p, params, c, balance, total, 0);
      updateTotal = true;
    }

    (amount, fee) = _swapAsset(value, minAmount, c, balance, total);
    if (amount > 0) {
      p.balances[params.token] = balance;
      updateTotal = true;
    }
  }

  function _calcParams(
    AssetBalancer storage p,
    address token,
    uint256 starvationBaseValue,
    bool checkSuspended
  ) private view returns (CalcParams memory c, uint256 flags) {
    AssetConfig storage config = p.configs[token];
    (c, flags) = _calcParams(p, starvationBaseValue, checkSuspended, config, config.price);
    State.require(flags & BF_EXTERNAL == 0);
  }

  function _calcParams(
    AssetBalancer storage p,
    uint256 starvationBaseValue,
    bool checkSuspended,
    AssetConfig storage config,
    uint256 price
  ) private view returns (CalcParams memory c, uint256 flags) {
    c.w = config.w;
    c.vA = price;

    flags = config.flags;
    if (flags & BF_SUSPENDED != 0 && checkSuspended) {
      revert Errors.OperationPaused();
    }
    if (flags & BF_FINISHED != 0) {
      flags <<= FINISHED_OFFSET;
    }

    uint256 mode = flags & (BF_SPM_CONSTANT | BF_SPM_MAX_WITH_CONST);
    if (mode != 0) {
      c.sA = flags & BF_SPM_GLOBAL == 0 ? config.spConst : p.spConst;
    }

    if (mode != BF_SPM_CONSTANT) {
      uint256 v;
      if (starvationBaseValue != 0 && c.vA != 0) {
        v = (flags & BF_SPM_GLOBAL == 0) == (mode != BF_SPM_MAX_WITH_CONST) ? config.n : p.spFactor;
        v = (starvationBaseValue * v).wadDiv(c.vA);
        if (flags & BF_EXTERNAL != 0) {
          v /= SP_EXTERNAL_N_BASE;
        }
      }
      if (flags & BF_SPM_MAX_WITH_CONST == 0 || v > c.sA) {
        c.sA = v;
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
    if (balance.accumAmount == 0) {
      return (0, 0);
    }

    uint256 k = _calcScale(c, balance, total);
    amount = _calcAmount(c, balance.accumAmount, value.rayMul(k));

    if (amount == 0 && c.sA != 0 && balance.accumAmount > 0) {
      amount = 1;
    }
    amount = balance.accumAmount - amount;

    if (amount >= minAmount && amount > 0) {
      balance.accumAmount = uint128(balance.accumAmount - amount);
      uint256 v = amount.wadMul(c.vA);
      total.accum = uint128(total.accum - v);

      if (v < value) {
        // This is a total amount of fees - it has 2 parts: balancing levy and volume penalty.
        fee = value - v;
        // The balancing levy can be positive (for popular assets) or negative (for non-popular assets) and is distributed within the balancer.
        // The volume penalty is charged on large transactions and can be taken out.

        // This formula is an aproximation that overestimates the levy and underpays the penalty. It is an acceptable behavior.
        // More accurate formula needs log() which may be an overkill for this case.
        k = (k + _calcScale(c, balance, total)) >> 1;
        // The negative levy is ignored here as it was applied with rayMul(k) above.
        k = k < WadRayMath.RAY ? value - value.rayMul(WadRayMath.RAY - k) : 0;

        // The constant-product formula (1/x) should produce enough fees than required by balancing levy ... but there can be gaps.
        fee = fee > k ? fee - k : 0;
      }
    } else {
      amount = 0;
    }
  }

  function _calcScale(
    CalcParams memory c,
    AssetBalance memory balance,
    Balances.RateAcc memory total
  ) private pure returns (uint256) {
    return
      balance.rateValue == 0 || total.accum == 0
        ? WadRayMath.RAY
        : ((uint256(balance.accumAmount) *
          c.vA +
          (balance.applyFrom > 0 ? WadRayMath.WAD * uint256(total.updatedAt - balance.applyFrom) * balance.rateValue : 0)).wadToRay().divUp(
            total.accum
          ) * total.rate).divUp(balance.rateValue);
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
    } else if (c.sA == 0) {
      a1 = 0;
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
    if (a == 0) {
      return 0;
    }

    if (cV > cA) {
      (cA, cV) = (cV, cA);
    }
    cV = cV * WadRayMath.RAY;

    return cV.mulDiv(cA, dV * WadRayMath.RAY + cV.mulDiv(cA, a));
  }

  function replenishAsset(
    AssetBalancer storage p,
    ReplenishParams memory params,
    uint256 incrementValue,
    uint96 newRate,
    uint96 lastRate,
    bool checkSuspended
  ) internal returns (bool fully) {
    Balances.RateAcc memory total = _syncTotalBalance(p);
    AssetBalance memory balance = p.balances[params.token];
    (CalcParams memory c, ) = _calcParams(p, params.token, balance.rateValue, checkSuspended);

    if (_replenishAsset(p, params, c, balance, total, incrementValue) < incrementValue) {
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
      balance.rateValue += newRate;
      total.rate += newRate;
    } else {
      unchecked {
        newRate = lastRate - newRate;
      }
      balance.rateValue -= newRate;
      total.rate -= newRate;
    }

    balance.applyFrom = _applyRateFrom(lastRate, newRate, balance.applyFrom, total.updatedAt);
  }

  function _replenishAsset(
    AssetBalancer storage p,
    ReplenishParams memory params,
    CalcParams memory c,
    AssetBalance memory assetBalance,
    Balances.RateAcc memory total,
    uint256 incrementValue
  ) private returns (uint256) {
    Sanity.require(total.updatedAt == block.timestamp);

    (uint256 receivedAmount, uint256 receivedValue, uint256 expectedValue) = params.replenishFn(params, incrementValue);
    if (receivedAmount == 0) {
      if (expectedValue == 0) {
        return 0;
      }
      receivedValue = 0;
    }

    uint256 v = receivedValue * WadRayMath.WAD + uint256(assetBalance.accumAmount) * c.vA;
    {
      total.accum = uint128(total.accum - expectedValue);
      Arithmetic.require((total.accum += uint128(receivedValue)) >= receivedValue);
      Arithmetic.require((assetBalance.accumAmount += uint128(receivedAmount)) >= receivedAmount);
    }

    if (assetBalance.accumAmount == 0) {
      v = expectedValue = 0;
    } else {
      v = v.divUp(assetBalance.accumAmount);
    }
    if (v != c.vA) {
      Arithmetic.require((c.vA = p.configs[params.token].price = uint144(v)) == v);
    }

    _applyRateFromBalanceUpdate(expectedValue, assetBalance, total);

    return receivedValue;
  }

  function _applyRateFromBalanceUpdate(
    uint256 expectedValue,
    AssetBalance memory assetBalance,
    Balances.RateAcc memory total
  ) private pure {
    if (assetBalance.applyFrom == 0 || assetBalance.rateValue == 0) {
      assetBalance.applyFrom = total.updatedAt;
    } else if (expectedValue > 0) {
      uint256 d = assetBalance.applyFrom + (uint256(expectedValue) + assetBalance.rateValue - 1) / assetBalance.rateValue;
      assetBalance.applyFrom = d < total.updatedAt ? uint32(d) : total.updatedAt;
    }
  }

  function _applyRateFrom(
    uint256 oldRate,
    uint256 newRate,
    uint32 applyFrom,
    uint32 current
  ) private pure returns (uint32) {
    if (oldRate == 0 || newRate == 0 || applyFrom == 0) {
      return current;
    }
    uint256 d = (oldRate * uint256(current - applyFrom) + newRate - 1) / newRate;
    return d >= current ? 1 : uint32(current - d);
  }

  function decRate(
    AssetBalancer storage p,
    address targetToken,
    uint96 lastRate
  ) internal returns (uint96 rate) {
    AssetBalance storage balance = p.balances[targetToken];
    rate = balance.rateValue;

    if (lastRate > 0) {
      Balances.RateAcc memory total = _syncTotalBalance(p);

      total.rate -= lastRate;
      p.totalBalance = total;

      (lastRate, rate) = (rate, rate - lastRate);
      (balance.rateValue, balance.applyFrom) = (rate, _applyRateFrom(lastRate, rate, balance.applyFrom, total.updatedAt));
    }
  }
}
