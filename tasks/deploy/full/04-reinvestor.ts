import { Contract } from 'ethers';

import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx, notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';
import { findOrDeployProxyFromCatalog, getDeployedProxy } from '../templates';

const catalogName = ProxyTypes.REINVESTOR;

deployTask(`full:deploy-reinvestor`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);
    const invConfig = cfg.Reinvestor;

    const cc = Factories.CollateralCurrencyV1.attach(getDeployedProxy(ProxyTypes.COLLATERAL_CCY));
    let found = await cc.borrowManager();

    const factory = Factories.ReinvestorV1;
    if (notFalsyOrZeroAddress(found)) {
      console.log(`Already deployed: ${found}`);
    } else {
      const initFunctionData = factory.interface.encodeFunctionData('initializeReinvestor');

      const [yd] = await findOrDeployProxyFromCatalog(factory, catalogName, initFunctionData);

      await mustWaitTx(cc.setBorrowManager(yd.address));
      found = yd.address;
    }

    const reinvestor = factory.attach(found);

    const enableStrategy = async (name: string, fn: () => Promise<[Contract, boolean]>) => {
      console.log('\t Deploying strategy:', name);
      const [s, newDeploy] = await fn();
      if (!newDeploy && (await reinvestor.isStrategy(s.address))) {
        console.log('\t\t already deployed');
        return;
      }
      await mustWaitTx(reinvestor.enableStrategy(s.address, true));
    };

    if (invConfig?.AAVE) {
      const sCfg = invConfig.AAVE;
      await enableStrategy(`AAVE v${sCfg.version}`, () =>
        getOrDeploy(Factories.AaveStrategy, '', [reinvestor.address, sCfg.pool, sCfg.version])
      );
    }
  })
);
