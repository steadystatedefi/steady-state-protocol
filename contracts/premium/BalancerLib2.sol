// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';

import 'hardhat/console.sol';

/**
  @dev This library conains core logic to balance multiple assets.
  There is a stream of premium value, which can be swapped into multiple assets, but each individual asset has not enough supply to cover the stream. 
  Giving all assets to a user by small portions is not a case either due to gas costs which can exceed the given value.
  So, the logic of this library allows a user to choose a subset of assets, and will either subsidize or penalize swap price based on demand vs supply.
  I.e. when available value of an asset compared to total value is higher than the supply rate of the asset vs total premium rate. then the price will be discounted.
  Addidionally, this library has mechanics to prevent depletion of assets by additional fees on large amount of an asset taken out or on depletion of an asset, and
  it utilizes constant-product formula.

  So, for each asset being swapped, amount of fees has 2 parts: balancing levy and volume penalty.
  The balancing levy can be positive (for popular assets) or negative (for non-popular assets) and is distributed within the balancer.
  The volume penalty is charged on large transactions (and depletions) and can be taken out.

  There is a "startvation" point - when asset's balance falls below this point then the constant-product formula is always applied. 
  The logic will attempt to invoke replenishment (before the actual swap) if a swap operation leads to a balance below this point.
  
  There are 8 modes to calculate vSP (value of the starvation point of an asset). 
  These modes are defined by a combination of BF_SPM_MAX_WITH_CONST, BF_SPM_CONSTANT, BF_SPM_GLOBAL flags set for asset's configuration.
  Also, there are 2 sets of the calculation flags per asset, and selection of a set depends on presence of BF_FINISHED.

  
  * AssetRateMultiplier = 0
    vSP = valueRate (asset's supply rate) * asset.calcConfig.n()

  * GlobalRateMultiplier = BF_SPM_GLOBAL
    vSP = valueRate (asset's supply rate) * assetBalanacer.spFactor

  * AssetConstant = BF_SPM_CONSTANT,
    vSP = asset.calcConfig.spConst

  * GlobalConstant = BF_SPM_CONSTANT | BF_SPM_GLOBAL,
    vSP = assetBalanacer.spConst

  * MaxOfAssetConstantAndGlobalRateMultiplier = BF_SPM_MAX_WITH_CONST,
    vSP = MAX(asset.calcConfig.spConst, valueRate * assetBalanacer.spFactor)

  * MaxOfGlobalConstantAndAssetRateMultiplier = BF_SPM_MAX_WITH_CONST | BF_SPM_GLOBAL,
    vSP = MAX(assetBalanacer.spConst, valueRate * asset.calcConfig.spFactor)

  * MaxOfAssetConstantAndAssetRateMultiplier = BF_SPM_MAX_WITH_CONST | BF_SPM_CONSTANT,
    vSP = MAX(asset.calcConfig.spConst, valueRate * asset.calcConfig.n())

  * MaxOfGlobalConstantAndGlobalRateMultiplier = BF_SPM_MAX_WITH_CONST | BF_SPM_CONSTANT | BF_SPM_GLOBAL,
    vSP = MAX(assetBalanacer.spConst, valueRate * assetBalanacer.spFactor)


  There are 2 types of assets
  * Normal asset
  * External asset - this one is tracked externally and is not cross-balanced with other assets. It is applied for drawdown of CC.

  This logic uses following terminology:
  * ACTUARY is a contract providing information about premium values and rates. Pushes the data.
  * SOURCE is a contract providing an asset to be swapped. Is pulled for the asset.

  NB! This logic strictly differentiate AMOUNT and VALUE of assets. 
  * AMOUNT is asset.balanceOf(), so it is counted in asset's token.
  * VALUE is amount*price, and is counted in CC (Coverage Currency). All rates are values, not amounts.
*/
library BalancerLib2 {
  using Math for uint256;
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;
  using CalcConfig for CalcConfigValue;

  /// @dev Balance of an asset within an AssetBalancer
  struct AssetBalance {
    /// @dev amount of the asset token
    uint128 accumAmount;
    /// @dev supply rate of the asset, as value per second
    uint96 rateValue;
    /// @dev timestamp since the rateValue applies
    uint32 applyFrom;
  }

  /// @dev Balancer itself. It has a set of assets (balances and rates) and provides balancing across them.
  struct AssetBalancer {
    /// @dev total VALUE balance and total VALUE rate of all sources
    Balances.RateAcc totalBalance;
    /// @dev asset balance and rate of all sources using this asset
    mapping(address => AssetBalance) balances; // [token]
    /// @dev asset balancing configuration
    mapping(address => AssetConfig) configs; // [token]
    /// @dev a global starvation value, for starvation point mode(s)
    uint160 spConst;
    /// @dev a global rate multiplier, for starvation point modes
    uint32 spFactor;
  }

  /// @dev Asset's balancing configuration
  struct AssetConfig {
    /// @dev balancing flags
    CalcConfigValue calc;
    /// @dev per asset starvation value, for starvation point mode(s)
    uint160 spConst;
  }

  /// @dev Set of im-memory value for calculations
  struct CalcParams {
    /// @dev amount of the asset at its starvation point
    uint256 sA;
    /// @dev target price of the asset, wad-based, actual type is uint192
    uint256 vA;
    /// @dev fee scaling factor for above-starvation values, [0..1], wad-based, actual type is uint64
    uint256 w;
  }

  /// @dev Parameters for replenishment callback to be called when the asset was depleted down to its starvation point.
  struct ReplenishParams {
    /// @dev An actuary for the replenishment. This field is not in use by the balacer, it is only for the callback.
    address actuary;
    /// @dev A source for the replenishment. This field is not in use by the balacer, it is only for the callback.
    address source;
    /// @dev An asset token to be replenished. Must be a valid and known asset.
    address token;
    /// @dev The callback to replenish the asset. It takes this struct and requestedValue - a recommended minimum value to be replenished.
    /// @dev The callback should return replenished amount and value (i.e. should use current price), and expectedValue.
    /// @dev The expectedValue is the value of asset expected to be returned by a source used for replenishment and considering its expected supply rate.
    /// @dev The balancer itself doesnt track sources, but it needs to know a difference between expected supply rate and actual replenishment.
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

  /// @dev Provides information about the asset
  /// @param p is a balancer
  /// @param token is an asset
  /// @return rawFlags x
  /// @return accum is amount of the asset belongs to the balancer
  /// @return stravation is amount of the asset at the starvation point
  /// @return price is a weighted price of the asset's balance
  /// @return w is a fee control factor
  /// @return valueRate is a supply rate of the asset
  /// @return since is a timestamp since the valueRate is applied
  function assetState(AssetBalancer storage p, address token)
    internal
    view
    returns (
      uint256 rawFlags,
      uint256 accum,
      uint256 stravation,
      uint256 price,
      uint256 w,
      uint256 valueRate,
      uint32 since
    )
  {
    AssetBalance memory balance = p.balances[token];
    (CalcParams memory c, CalcConfigValue flags) = _calcParams(p, token, balance.rateValue, false);
    return (flags.flags(), balance.accumAmount, c.sA, c.vA, c.w, balance.rateValue, balance.applyFrom);
  }

  /// @dev Swaps the premium value for CC (drawdown). This oparation is only applicable to CC (value and amount considered to be equal).
  /// @param p is a balancer
  /// @param token is an asset (should be marked as external)
  /// @param value is value to be swapped
  /// @param minAmount is a miminum allowed amount of the asset to be returned, otherwise swap will not be performed (will return zero).
  /// @param assetAmount is an amount of the asset available externally
  /// @param assetFreeAllowance is an amount of the asset which can be redeemed with a minimal fee or without it.
  /// @return amount of the asset to be given out (when zero, `value` should not be taken)
  /// @return fee (the penalty part) to taken from the value
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

  /// @dev Swaps the premium value for CC (drawdown) as a part of batch swap. This oparation is only applicable to CC (value and amount considered to be equal).
  /// @dev This call allows to avoid slippage of the total balance introduced by individual swaps, hance takes a smaller fee.
  /// @param p is a balancer
  /// @param token is an asset (should be marked as external)
  /// @param value is value to be swapped
  /// @param minAmount is a miminum allowed amount of the asset to be returned, otherwise swap will not be performed (will return zero).
  /// @param assetAmount is an amount of the asset available externally
  /// @param assetFreeAllowance is an amount of the asset which can be redeemed with a minimal fee or without it.
  /// @param total is the total balance of values and supply rates of all assets of the balancer
  /// @return amount of the asset to be given out (when zero, `value` should not be taken)
  /// @return fee (the penalty part) to taken from the value
  function swapExternalAssetInBatch(
    AssetBalancer storage p,
    address token,
    uint256 value,
    uint256 minAmount,
    uint256 assetAmount,
    uint256 assetFreeAllowance,
    Balances.RateAcc memory total
  ) internal view returns (uint256 amount, uint256 fee) {
    total.sync(uint32(block.timestamp));

    Arithmetic.require((total.accum += uint128(assetAmount)) >= assetAmount);
    if (assetFreeAllowance > assetAmount) {
      assetFreeAllowance = assetAmount;
    }

    // amount EQUALS value
    (CalcParams memory c, CalcConfigValue flags) = _calcParams(p, assetFreeAllowance, true, p.configs[token], WadRayMath.WAD, assetAmount);
    State.require(flags.isExternal());

    AssetBalance memory balance;
    balance.accumAmount = uint128(assetAmount);
    // balance.rateValue = 0 suppresses cross-asset balancing
    (amount, fee) = _swapAsset(value, minAmount, c, balance, total);
  }

  /// @dev Swaps the premium value for an asset. The asset should NOT be marked as external.
  /// @param p is a balancer
  /// @param params for replenishment (the asset / token is defined inside it)
  /// @param value is value to be swapped
  /// @param minAmount is a miminum allowed amount of the asset to be returned, otherwise swap will not be performed (will return zero).
  /// @return amount of the asset to be given out (when zero, `value` should not be taken)
  /// @return fee (the penalty part) to taken from the value
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

  /// @dev Swaps the premium value for an asset. The asset should NOT be marked as external.
  /// @dev This call allows to avoid slippage of the total balance introduced by individual swaps, hance takes a smaller fee.
  /// @param p is a balancer
  /// @param params for replenishment (the asset / token is defined inside it)
  /// @param value is value to be swapped
  /// @param minAmount is a miminum allowed amount of the asset to be returned, otherwise swap will not be performed (will return zero).
  /// @param total is the total balance of values and supply rates of all assets of the balancer
  /// @return amount of the asset to be given out (when zero, `value` should not be taken)
  /// @return fee (the penalty part) to taken from the value
  /// @return updateTotal is true when the total was updated and should be stored.
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

    (CalcParams memory c, CalcConfigValue flags) = _calcParams(p, params.token, balance.rateValue, true);

    if (flags.isAutoReplenish() || (balance.rateValue > 0 && balance.accumAmount <= c.sA)) {
      _replenishAsset(p, params, c, balance, total, 0);
      updateTotal = true;
    }

    (amount, fee) = _swapAsset(value, minAmount, c, balance, total);
    if (amount > 0) {
      p.balances[params.token] = balance;
      updateTotal = true;
    }
  }

  /// @dev Checks assets state and prepares calculation params
  function _calcParams(
    AssetBalancer storage p,
    address token,
    uint256 starvationBaseValue,
    bool checkSuspended
  ) private view returns (CalcParams memory c, CalcConfigValue flags) {
    AssetConfig storage config = p.configs[token];
    (c, flags) = _calcParams(p, starvationBaseValue, checkSuspended, config, config.calc.price(), 0);
    State.require(!flags.isExternal());
  }

  function _calcParams(
    AssetBalancer storage p,
    uint256 starvationBaseValue,
    bool checkSuspended,
    AssetConfig storage ac,
    uint256 price,
    uint256 extBase
  ) private view returns (CalcParams memory c, CalcConfigValue calc) {
    calc = ac.calc;
    c.w = calc.w();
    c.vA = price;

    if (checkSuspended && calc.isSuspended()) {
      revert Errors.OperationPaused();
    }

    uint8 flags = calc.calcFlags();

    uint256 mode = flags & (CalcConfig.BF_SPM_CONSTANT | CalcConfig.BF_SPM_MAX_WITH_CONST);
    if (mode != 0) {
      c.sA = flags & CalcConfig.BF_SPM_GLOBAL == 0 ? ac.spConst : p.spConst;
    }

    if (mode != CalcConfig.BF_SPM_CONSTANT) {
      uint256 v;
      if (c.vA != 0) {
        if (starvationBaseValue != 0) {
          v = starvationBaseValue * ((flags & CalcConfig.BF_SPM_GLOBAL == 0) == (mode != CalcConfig.BF_SPM_MAX_WITH_CONST) ? calc.n() : p.spFactor);
        }
        if (extBase > 0) {
          v = extBase.boundedSub(v / CalcConfig.SP_EXTERNAL_N_BASE);
        }
        v = v.wadDiv(c.vA);
      }
      if (flags & CalcConfig.BF_SPM_MAX_WITH_CONST == 0 || v > c.sA) {
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

  /// @dev Calculates cross-asset balancing factor
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

  /// @dev Calculates asset amount to be given for value `dV` at the current amount `a` (point on the curve)
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

  /// @dev Calculates asset amount (single CP curve) to be given for value `dV` at the current amount `a` (point on the curve)
  function _calcCurve(
    CalcParams memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256) {
    return _calc(a, dV, a, a.wadMul(c.vA));
  }

  /// @dev Calculates asset amount (dual CP curve) to be given for value `dV` at the current amount `a` (point on the curve)
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

  /// @dev Calculates asset amount (flat then CP curve) to be given for value `dV` at the current amount `a` (point on the curve)
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

  /// @dev Calculates asset amount (single CP curve starting at starvation) to be given for value `dV` at the current amount `a`.
  function _calcStarvation(
    CalcParams memory c,
    uint256 a,
    uint256 dV
  ) private pure returns (uint256 a1) {
    a1 = _calc(a, dV, c.sA, c.sA.wadMul(c.vA));
  }

  /// @dev Higher-resolution implementation of the CP function. cA and cV are the "constant" components.
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

  /// @dev Performs replenishment and update of the supply rate of an asset.
  /// @dev When the source will not be able to provide the requred replenishment value, then its supply rate will be forced to zero.
  /// @param p is a balancer
  /// @param params for replenishment (the asset / token is defined inside it)
  /// @param incrementValue is value expected to be replenished
  /// @param newRate is the new rate for the source being replenished
  /// @param lastRate is the last known rate for the source being replenished
  /// @return fully is true the source has provided asset of value at least equal to `incrementValue`
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
      Arithmetic.require((c.vA = uint144(v)) == v);

      AssetConfig storage ac = p.configs[params.token];
      ac.calc = ac.calc.setPrice(uint144(v));
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

  /// @dev Decrements asset's supply rate. This function is applied when a source is removed.
  /// @param p is a balancer
  /// @param targetToken is an asset
  /// @param lastRate is the last known rate for the source being removed
  /// @return rate of supply for the asset after this update
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

/** @dev Packed configuration of balancer for an asset. It is an equivalent of
    struct CalcConfigValue {
      uint144 price;
      uint64 w;
      uint32 n;
      uint16 flags;
    }

    NB! This configuartion has 2 sets of flags - for an active asset, and for a "finished" asset - an asset without supply.
*/
type CalcConfigValue is uint256;

library CalcConfig {
  /// @dev An offset for flags when BF_FINISHED is present.
  uint8 private constant FINISHED_OFFSET = 8;

  uint16 internal constant BF_SPM_GLOBAL = 1 << 0;
  uint16 internal constant BF_SPM_CONSTANT = 1 << 1;
  uint16 internal constant BF_SPM_MAX_WITH_CONST = 1 << 2;

  /// @dev A source will be pulled at every swap (not by reaching the starvation point)
  uint16 internal constant BF_AUTO_REPLENISH = 1 << 6;
  /// @dev There are no sources for this asset
  uint16 internal constant BF_FINISHED = 1 << 7;

  uint16 private constant BF_SPM_MASK = BF_SPM_GLOBAL | BF_SPM_CONSTANT | BF_SPM_MAX_WITH_CONST;

  /// @dev This is a base applied to N when the asset is external.
  uint32 internal constant SP_EXTERNAL_N_BASE = 1_00_00;

  /// @dev This asset is external
  uint16 internal constant BF_EXTERNAL = 1 << 14;
  /// @dev This asset is suspended / paused
  uint16 internal constant BF_SUSPENDED = 1 << 15;

  /// @return target asset price, wad-based
  function price(CalcConfigValue v) internal pure returns (uint144) {
    return uint144(CalcConfigValue.unwrap(v));
  }

  uint8 private constant OFS_W = 144;

  /// @return [0..1] wad-based, fee control factor
  function w(CalcConfigValue v) internal pure returns (uint64) {
    return uint64(CalcConfigValue.unwrap(v) >> OFS_W);
  }

  uint8 private constant OFS_N = OFS_W + 64;

  /// @return pre-asset rate multiplier, for starvation point modes
  function n(CalcConfigValue v) internal pure returns (uint32) {
    return uint32(CalcConfigValue.unwrap(v) >> OFS_N);
  }

  uint8 private constant OFS_FLAGS = OFS_N + 32;

  /// @return all flags
  function flags(CalcConfigValue v) internal pure returns (uint16) {
    return uint16(CalcConfigValue.unwrap(v) >> OFS_FLAGS);
  }

  /// @return calculation flags (starvation point mode) based on asset's 'finished' state
  function calcFlags(CalcConfigValue v) internal pure returns (uint8) {
    uint256 u = flags(v);
    if (u & BF_FINISHED != 0) {
      u >>= FINISHED_OFFSET;
    }
    return uint8(u & BF_SPM_MASK);
  }

  function isZero(CalcConfigValue v) internal pure returns (bool) {
    return CalcConfigValue.unwrap(v) == 0;
  }

  function newValue(
    uint144 price_,
    uint64 w_,
    uint32 n_,
    uint16 flags_
  ) internal pure returns (CalcConfigValue) {
    return CalcConfigValue.wrap(price_ | (uint256(w_) << OFS_W) | (uint256(n_) << OFS_N) | (uint256(flags_) << OFS_FLAGS));
  }

  function setPrice(CalcConfigValue v, uint144 price_) internal pure returns (CalcConfigValue) {
    uint256 u = CalcConfigValue.unwrap(v) >> OFS_W;
    return CalcConfigValue.wrap((u << OFS_W) | price_);
  }

  function _setFlag(
    CalcConfigValue v,
    uint256 flag,
    bool set
  ) private pure returns (CalcConfigValue) {
    uint256 u = CalcConfigValue.unwrap(v);
    return CalcConfigValue.wrap(set ? u | flag : u & ~flag);
  }

  uint256 private constant FLAG_BF_SUSPENDED = uint256(BF_SUSPENDED) << OFS_FLAGS;

  function setSuspended(CalcConfigValue v, bool suspended) internal pure returns (CalcConfigValue) {
    return _setFlag(v, FLAG_BF_SUSPENDED, suspended);
  }

  function isSuspended(CalcConfigValue v) internal pure returns (bool) {
    return CalcConfigValue.unwrap(v) & FLAG_BF_SUSPENDED != 0;
  }

  uint256 private constant FLAG_BF_FINISHED = uint256(BF_FINISHED) << OFS_FLAGS;

  function setFinished(CalcConfigValue v) internal pure returns (CalcConfigValue) {
    return CalcConfigValue.wrap(CalcConfigValue.unwrap(v) | FLAG_BF_FINISHED);
  }

  uint256 private constant FLAG_BF_AUTO_REPLENISH = uint256(BF_AUTO_REPLENISH) << OFS_FLAGS;

  function setAutoReplenish(CalcConfigValue v, bool autoReplenish) internal pure returns (CalcConfigValue) {
    return _setFlag(v, FLAG_BF_AUTO_REPLENISH, autoReplenish);
  }

  function isAutoReplenish(CalcConfigValue v) internal pure returns (bool) {
    return CalcConfigValue.unwrap(v) & FLAG_BF_AUTO_REPLENISH != 0;
  }

  uint256 private constant FLAG_BF_EXTERNAL = uint256(BF_EXTERNAL) << OFS_FLAGS;

  function isExternal(CalcConfigValue v) internal pure returns (bool) {
    return CalcConfigValue.unwrap(v) & FLAG_BF_EXTERNAL != 0;
  }
}
