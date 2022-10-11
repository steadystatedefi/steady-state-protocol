import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';
import { findOrDeployProxyFromCatalog, getDeployedProxy } from '../templates';

deployTask(`full:deploy-index-pools`, `Deploy index pools`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const ac = Factories.AccessController.get();
    const pfFactory = Factories.PremiumFundV1;
    const pf = pfFactory.attach(getDeployedProxy(ProxyTypes.PREMIUM_FUND));
    const cc = Factories.CollateralCurrencyV1.attach(getDeployedProxy(ProxyTypes.COLLATERAL_CCY));

    let index = 0;
    for (const poolInfo of cfg.IndexPools) {
      index += 1;

      const factory = Factories.ImperpetualPoolV1; // TODO this needs to be based on poolInfo.poolType
      const initFunctionData = factory.interface.encodeFunctionData(poolInfo.initializer, [
        poolInfo.governor ?? zeroAddress(),
        ...poolInfo.initParams,
      ]);

      const [pool, newDeploy] = await findOrDeployProxyFromCatalog(
        factory,
        poolInfo.poolType,
        initFunctionData,
        `${index}`
      );

      if (newDeploy || !(await cc.isRegistered(pool.address))) {
        if (newDeploy || (await pf.getActuaryState(pool.address)) === 0) {
          await mustWaitTx(pool.setPremiumDistributor(pf.address));
          await mustWaitTx(pf.registerPremiumActuary(pool.address, true));
        }
        await mustWaitTx(ac.grantRoles(pool.address, AccessFlags.INSURER_POOL_LISTING));
        await mustWaitTx(cc.registerInsurer(pool.address));
      }
    }
  })
);
