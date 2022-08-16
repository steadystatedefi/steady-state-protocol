import { zeroAddress } from 'ethereumjs-util';

import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { deployTask } from '../deploy-steps';
import { deployProxyFromCatalog } from '../templates';

const catalogName = ProxyTypes.INSURED_POOL;

deployTask(`dev:deploy-insured-pools`, `Deploy insured pools`, __dirname).setAction(
  dreAction(async () => {
    const factory = Factories.InsuredPoolV1;
    const initFunctionData = factory.interface.encodeFunctionData('initializeInsured', [zeroAddress()]);

    await deployProxyFromCatalog(catalogName, initFunctionData);
  })
);
