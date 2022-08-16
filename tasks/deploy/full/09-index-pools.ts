import { zeroAddress } from 'ethereumjs-util';

import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';
import { deployProxyFromCatalog, getDeployedProxy } from '../templates';

deployTask(`full:deploy-index-pools`, `Deploy index pools`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const pfFactory = Factories.PremiumFundV1;
    const pf = pfFactory.attach(getDeployedProxy(ProxyTypes.PREMIUM_FUND));
    const cc = Factories.CollateralCurrency.get();

    let index = 0;
    for (const poolInfo of cfg.IndexPools) {
      index += 1;

      const factory = Factories.ImperpetualPoolV1; // TODO this needs to be based on poolInfo.poolType
      const initFunctionData = factory.interface.encodeFunctionData(poolInfo.initializer, [
        poolInfo.governor ?? zeroAddress(),
        ...poolInfo.initParams,
      ]);

      const poolAddr = await deployProxyFromCatalog(poolInfo.poolType, initFunctionData, `${index}`);
      const pool = factory.attach(poolAddr);

      await mustWaitTx(pool.setPremiumDistributor(pf.address));
      await mustWaitTx(pf.registerPremiumActuary(pool.address, true));
      await mustWaitTx(cc.registerInsurer(pool.address));
    }
  })
);
