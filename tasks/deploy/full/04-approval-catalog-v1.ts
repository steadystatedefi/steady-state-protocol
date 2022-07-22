import { BigNumber } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addContractToJsonDb } from '../../../helpers/deploy-db';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const APPROVAL_CATALOG = BigNumber.from(1).shl(16);

deployTask(`full:deploy-approval-catalog`, `Deploy ${EContractId.ApprovalCatalogV1}`, __dirname).setAction(
  async (_, localBRE) => {
    await localBRE.run('set-DRE');

    const existedApprovalCatalogV1Address = Factories.ApprovalCatalogV1.findInstance(EContractId.ApprovalCatalogV1);

    if (!falsyOrZeroAddress(existedApprovalCatalogV1Address)) {
      console.log(`Already deployed ${EContractId.ApprovalCatalogV1}:`, existedApprovalCatalogV1Address);
      return;
    }

    const proxyCatalogAddress = Factories.ProxyCatalog.findInstance(EContractId.ProxyCatalog);

    if (falsyOrZeroAddress(proxyCatalogAddress)) {
      throw new Error(
        `${EContractId.ProxyCatalog} hasn't been deployed yet. Please, deploy ${EContractId.ProxyCatalog} first`
      );
    }

    const accessControllerAddress = Factories.AccessController.findInstance(EContractId.AccessController);

    if (falsyOrZeroAddress(accessControllerAddress)) {
      throw new Error(
        `${EContractId.AccessController} hasn't been deployed yet. Please, deploy ${EContractId.AccessController} first.`
      );
    }

    const deployer = await getFirstSigner();
    const proxyCatalog = Factories.ProxyCatalog.get(deployer, EContractId.ProxyCatalog);
    const accessController = Factories.AccessController.get(deployer, EContractId.AccessController);

    const approvalCatalogV1 = await Factories.ApprovalCatalogV1.connectAndDeploy(
      deployer,
      EContractId.ApprovalCatalogV1,
      [accessController.address]
    );
    await waitForTx(approvalCatalogV1.deployTransaction);

    console.log(`${EContractId.ApprovalCatalogV1}:`, approvalCatalogV1.address);

    await waitForTx(
      await proxyCatalog.addAuthenticImplementation(
        approvalCatalogV1.address,
        formatBytes32String(EContractId.ApprovalCatalog)
      )
    );
    await waitForTx(await proxyCatalog.setDefaultImplementation(approvalCatalogV1.address));

    let approvalCatalogProxyAddress = '';

    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxyWithImpl(
        deployer.address,
        formatBytes32String(EContractId.ApprovalCatalog),
        approvalCatalogV1.address,
        approvalCatalogV1.interface.encodeFunctionData('initializeApprovalCatalog')
      ),
      (event) => {
        approvalCatalogProxyAddress = event.proxy;
      }
    );

    console.log(`${EContractId.ApprovalCatalog}:`, approvalCatalogProxyAddress);

    const approvalCatalogProxy = Factories.TransparentProxy.attach(approvalCatalogProxyAddress);
    addContractToJsonDb(EContractId.ApprovalCatalog, approvalCatalogProxy, true, []);

    await waitForTx(await accessController.setProtection(APPROVAL_CATALOG, false));
    await waitForTx(await accessController.setAddress(APPROVAL_CATALOG, approvalCatalogProxyAddress));
    await waitForTx(await accessController.setProtection(APPROVAL_CATALOG, true));

    console.log(`${EContractId.ApprovalCatalog} was successfully added to ${EContractId.AccessController}`);
  }
);
