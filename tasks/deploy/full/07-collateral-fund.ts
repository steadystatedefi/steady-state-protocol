import { zeroAddress } from 'ethereumjs-util';

import { loadNetworkConfig } from '../../../helpers/config-loader';
import { getAssetAddress } from '../../../helpers/config-types';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog } from './templates';

const catalogName = ProxyTypes.COLLATERAL_FUND;

deployTask(`full:deploy-collateral-fund`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const factory = Factories.CollateralFundV1;
    const cc = Factories.CollateralCurrency.get();
    const initFunctionData = factory.interface.encodeFunctionData('initializeCollateralFund');

    const collateralFundAddr = await deployProxyFromCatalog(catalogName, initFunctionData);

    if (!(await cc.isLiquidityProvider(collateralFundAddr))) {
      await mustWaitTx(cc.registerLiquidityProvider(collateralFundAddr));
    }

    const collateralFund = factory.attach(collateralFundAddr);

    if (cfg.CollateralFund.assets) {
      const cfgAssets = Object.entries(cfg.CollateralFund.assets);
      const addedAssets: Set<string> = new Set();
      (await collateralFund.assets()).forEach((addr) => addedAssets.add(addr));

      const assetNames: string[] = [];
      const assetAddrs: string[] = [];
      const assetTrustees: string[] = [];

      cfgAssets.forEach(([assetName, assetInfo]) => {
        if (!assetInfo) {
          return;
        }
        assetAddrs.push(getAssetAddress(cfg, assetName));
        assetNames.push(assetName);
        assetTrustees.push(assetInfo.trustee ?? zeroAddress());
      });

      if (assetAddrs.length > 0) {
        for (let i = 0; i < assetAddrs.length; i++) {
          console.log('Adding asset: ', assetNames[i], assetAddrs[i]);
          await mustWaitTx(collateralFund.addAsset(assetAddrs[i], assetTrustees[i]));
        }
      }
    }
  })
);
