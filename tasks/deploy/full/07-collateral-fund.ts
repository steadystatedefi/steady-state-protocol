import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { loadNetworkConfig } from '../../../helpers/config-loader';
import { getAssetAddress } from '../../../helpers/config-types';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { falsyOrZeroAddress, mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';
import { findOrDeployProxyFromCatalog } from '../templates';

const catalogName = ProxyTypes.COLLATERAL_FUND;

deployTask(`full:deploy-collateral-fund`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const ac = Factories.AccessController.get();

    const factory = Factories.CollateralFundV1;
    const cc = Factories.CollateralCurrency.get();
    const initFunctionData = factory.interface.encodeFunctionData('initializeCollateralFund');

    const [collateralFund, newDeploy] = await findOrDeployProxyFromCatalog(factory, catalogName, initFunctionData);

    if (newDeploy || !(await cc.isLiquidityProvider(collateralFund.address))) {
      await mustWaitTx(ac.grantRoles(collateralFund.address, AccessFlags.COLLATERAL_FUND_LISTING));
      await mustWaitTx(cc.registerLiquidityProvider(collateralFund.address));
    }

    if (cfg.CollateralFund.assets) {
      const cfgAssets = Object.entries(cfg.CollateralFund.assets);
      const knownAssets: Set<string> = new Set();
      if (!newDeploy) {
        (await collateralFund.assets()).forEach((addr) => knownAssets.add(addr.toUpperCase()));
      }

      const assetNames: string[] = [];
      const assetAddrs: string[] = [];
      const assetTrustees: string[] = [];

      cfgAssets.forEach(([assetName, assetInfo]) => {
        if (!assetInfo) {
          return;
        }
        const assetAddr = getAssetAddress(cfg, assetName);
        if (falsyOrZeroAddress(assetAddr) || knownAssets.has(assetAddr.toUpperCase())) {
          return;
        }

        assetAddrs.push(assetAddr);
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
