import { zeroAddress } from 'ethereumjs-util';
import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addProxyToJsonDb } from '../../../helpers/deploy-db';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { falsyOrZeroAddress, mustWaitTx, notFalsyOrZeroAddress, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const factory = Factories.ApprovalCatalogV1;

deployTask(`full:deploy-approval-catalog`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async () => {
    const accessController = Factories.AccessController.get();
    const proxyCatalog = Factories.ProxyCatalog.get();
    const cc = Factories.CollateralCurrency.get();
    const PROXY_TYPE = formatBytes32String('APPROVAL_CATALOG');

    if (falsyOrZeroAddress(await proxyCatalog.getDefaultImplementation(PROXY_TYPE, cc.address))) {
      const [impl] = await getOrDeploy(factory, '', () => ({
        args: [accessController.address] as [string],
      }));

      await mustWaitTx(proxyCatalog.addAuthenticImplementation(impl.address, PROXY_TYPE, cc.address));
      await mustWaitTx(proxyCatalog.setDefaultImplementation(impl.address));
    }

    const approvalCatalog = await accessController.getAddress(AccessFlags.APPROVAL_CATALOG);
    if (notFalsyOrZeroAddress(approvalCatalog)) {
      console.log(`Already deployed ApprovalCatalog: ${approvalCatalog}`);
    } else {
      const initFunctionData = factory.attach(zeroAddress()).interface.encodeFunctionData('initializeApprovalCatalog');

      let approvalCatalogAddr = '';
      let approvalCatalogImpl = '';
      await Events.ProxyCreated.waitOne(
        proxyCatalog.createProxy(zeroAddress(), PROXY_TYPE, zeroAddress(), initFunctionData),
        (event) => {
          approvalCatalogAddr = event.proxy;
          approvalCatalogImpl = event.impl;
        }
      );

      console.log(`ApprovalCatalog: ${approvalCatalogAddr} => ${approvalCatalogImpl}`);

      await waitForTx(await accessController.setAddress(AccessFlags.APPROVAL_CATALOG, approvalCatalogAddr));

      addProxyToJsonDb(EContractId.ApprovalCatalog, approvalCatalogAddr, approvalCatalogImpl, '', [
        proxyCatalog.address,
        approvalCatalogImpl,
        initFunctionData,
      ]);
    }
  })
);
