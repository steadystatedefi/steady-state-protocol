import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx, notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';
import { deployProxyFromCatalog } from '../templates';

const catalogName = ProxyTypes.YIELD_DISTRIBUTOR;

deployTask(`full:deploy-yield-distributor`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const cc = Factories.CollateralCurrency.get();
    const found = await cc.borrowManager();

    if (notFalsyOrZeroAddress(found)) {
      console.log(`Already deployed: ${found}`);
      return;
    }

    const factory = Factories.YieldDistributorV1;
    const initFunctionData = factory.interface.encodeFunctionData('initializeYieldDistributor');

    const addr = await deployProxyFromCatalog(factory, catalogName, initFunctionData);

    await mustWaitTx(cc.setBorrowManager(addr));
  })
);
