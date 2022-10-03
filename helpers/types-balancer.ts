import { BigNumber } from 'ethers';

import { MAX_UINT144, MAX_UINT32, MAX_UINT64 } from './constants';

export const BalancerCalcConfig = {
  BF_SPM_GLOBAL: 1 << 0,
  BF_SPM_CONSTANT: 1 << 1,
  BF_SPM_MAX_WITH_CONST: 1 << 2,

  BF_AUTO_REPLENISH: 1 << 6, // pull a source at every swap
  BF_FINISHED: 1 << 7, // no more sources for this token

  BF_EXTERNAL: 1 << 14,
  BF_SUSPENDED: 1 << 15, // token is suspended

  SP_EXTERNAL_N_BASE: 1_00_00,

  encodeRaw: (price: BigNumber, w: BigNumber, n: BigNumber, flags: number): BigNumber => {
    // [144] price
    // [64] w
    // [32] n
    // [16] flags

    if (MAX_UINT144.lt(price)) {
      throw new Error('price is too high');
    }
    if (MAX_UINT64.lt(w)) {
      throw new Error('w is too high');
    }
    if (MAX_UINT32.lt(n)) {
      throw new Error('n is too high');
    }
    if (flags > 65535) {
      throw new Error('flags is too high');
    }
    return BigNumber.from(flags).shl(32).or(n).shl(64).or(w).shl(144).or(price);
  },

  encode: (
    price: BigNumber,
    w: BigNumber,
    n: BigNumber,
    mode?: BalancerAssetMode,
    modeFinished?: BalancerAssetMode,
    autoReplenish?: boolean,
    external?: boolean,
    suspended?: boolean
  ): BigNumber => {
    let flags: number = modeFinished ?? 0;
    flags <<= 8;
    flags |= mode ?? 0;

    if (autoReplenish) {
      flags |= BalancerCalcConfig.BF_AUTO_REPLENISH;
    }
    if (external) {
      flags |= BalancerCalcConfig.BF_EXTERNAL;
    }
    if (suspended) {
      flags |= BalancerCalcConfig.BF_SUSPENDED;
    }
    return BalancerCalcConfig.encodeRaw(price, w, n, flags);
  },
};

export enum BalancerAssetMode {
  AssetRateMultiplier = 0, //
  GlobalRateMultiplier = BalancerCalcConfig.BF_SPM_GLOBAL,
  AssetConstant = BalancerCalcConfig.BF_SPM_CONSTANT,
  GlobalConstant = BalancerCalcConfig.BF_SPM_CONSTANT | BalancerCalcConfig.BF_SPM_GLOBAL,

  MaxOfAssetConstantAndGlobalRateMultiplier = BalancerCalcConfig.BF_SPM_MAX_WITH_CONST,
  MaxOfGlobalConstantAndAssetRateMultiplier = BalancerCalcConfig.BF_SPM_MAX_WITH_CONST |
    BalancerCalcConfig.BF_SPM_GLOBAL,
  MaxOfAssetConstantAndAssetRateMultiplier = BalancerCalcConfig.BF_SPM_MAX_WITH_CONST |
    BalancerCalcConfig.BF_SPM_CONSTANT,
  MaxOfGlobalConstantAndGlobalRateMultiplier = BalancerCalcConfig.BF_SPM_MAX_WITH_CONST |
    BalancerCalcConfig.BF_SPM_CONSTANT |
    BalancerCalcConfig.BF_SPM_GLOBAL,
}
