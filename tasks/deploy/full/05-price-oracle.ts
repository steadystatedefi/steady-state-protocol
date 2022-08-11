import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { notFalsyOrZeroAddress, waitForTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog } from './templates';

const catalogName = ProxyTypes.ORACLE_ROUTER;

deployTask(`full:deploy-price-oracle`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const factory = Factories.OracleRouterV1;

    const accessController = Factories.AccessController.get();
    const accessFlag = AccessFlags.PRICE_ROUTER;

    const found = await accessController.getAddress(accessFlag);
    if (notFalsyOrZeroAddress(found)) {
      console.log(`Already deployed: ${found}`);
      return;
    }

    const initFunctionData = factory.interface.encodeFunctionData('initializePriceOracle');
    const addr = await deployProxyFromCatalog(catalogName, initFunctionData, '', zeroAddress());

    await waitForTx(await accessController.setAddress(accessFlag, addr));

    // TODO configure sources and tokens
  })
);
