import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { notFalsyOrZeroAddress, waitForTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog } from './templates';

const catalogName = ProxyTypes.APPROVAL_CATALOG;

deployTask(`full:deploy-approval-catalog`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const accessController = Factories.AccessController.get();
    const accessFlag = AccessFlags.APPROVAL_CATALOG;
    const factory = Factories.ApprovalCatalogV1;

    const found = await accessController.getAddress(accessFlag);
    if (notFalsyOrZeroAddress(found)) {
      console.log(`Already deployed: ${found}`);
      return;
    }

    const initFunctionData = factory.attach(zeroAddress()).interface.encodeFunctionData('initializeApprovalCatalog');
    const addr = await deployProxyFromCatalog(catalogName, initFunctionData, '', zeroAddress());

    await waitForTx(await accessController.setAddress(accessFlag, addr));
  })
);
