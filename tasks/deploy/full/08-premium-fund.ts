import { BigNumber, utils } from 'ethers';

import { loadNetworkConfig } from '../../../helpers/config-loader';
import { IPremiumTokenConfig } from '../../../helpers/config-types';
import { ZERO, ZERO_ADDRESS } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { falsyOrZeroAddress, mustWaitTx, notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';
import { EthereumAddress } from '../../../helpers/types';
import { BalancerCalcConfig } from '../../../helpers/types-balancer';
import { BalancerLib2 } from '../../../types/contracts/premium/PremiumFundBase';
import { deployTask } from '../deploy-steps';
import { findOrDeployProxyFromCatalog } from '../templates';

const catalogName = ProxyTypes.PREMIUM_FUND;

deployTask(`full:deploy-premium-fund`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);
    const pfConfig = cfg.PremiumFund;

    const factory = Factories.PremiumFundV1;
    const initFunctionData = factory.interface.encodeFunctionData('initializePremiumFund');

    const [pf, newDeploy] = await findOrDeployProxyFromCatalog(factory, catalogName, initFunctionData);

    const setAssetConfig = async (
      actuary: EthereumAddress,
      asset: EthereumAddress,
      c: IPremiumTokenConfig
    ): Promise<void> => {
      const assetCfg = prepareAssetConfig(c, notFalsyOrZeroAddress(asset));

      if (!newDeploy) {
        const curentCfg = await pf.getAssetConfig(actuary, asset);
        if (curentCfg.calc.eq(assetCfg.calc) && curentCfg.spConst.eq(assetCfg.spConst)) {
          console.log('\t Already set');
          return;
        }
      }
      await mustWaitTx(pf.setAssetConfig(actuary, asset, assetCfg));
    };

    console.log('Default config for premium asset');
    await setAssetConfig(ZERO_ADDRESS, ZERO_ADDRESS, pfConfig.premiumTokenConfig);

    console.log('Default config for drawdown asset');
    const cc = await pf.collateral();
    if (falsyOrZeroAddress(cc)) {
      throw new Error('Missing collateral currency');
    }
    await setAssetConfig(ZERO_ADDRESS, cc, pfConfig.drawdownTokenConfig);

    const setGlobals = async (
      actuary: EthereumAddress,
      globalConstSP: BigNumber,
      globalFactorSP: number
    ): Promise<void> => {
      const curentCfg = newDeploy ? ([ZERO, 0] as const) : await pf.getActuaryGlobals(actuary);
      if (curentCfg[0].eq(globalConstSP) && curentCfg[1] === globalFactorSP) {
        console.log('\t Already set');
        return;
      }
      await pf.setActuaryGlobals(actuary, globalConstSP, globalFactorSP);
    };

    console.log('Default config for actuary constants');
    await setGlobals(ZERO_ADDRESS, pfConfig.globalConstSP ?? ZERO, pfConfig.globalFactorSP ?? 0);
  })
);

function prepareAssetConfig(c: IPremiumTokenConfig, external: boolean): BalancerLib2.AssetConfigStruct {
  if (c.w < 0 || c.w > 1) {
    throw new Error('w must be [0..1]');
  }
  const w = utils.parseUnits(c.w.toFixed());

  return {
    calc: BalancerCalcConfig.encode(ZERO, w, BigNumber.from(c.n), c.mode, c.modeFinished, c.autoReplenish, external),
    spConst: c.constSP ?? ZERO,
  };
}
