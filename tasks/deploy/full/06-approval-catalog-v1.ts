import { BigNumber } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addProxyToJsonDb } from '../../../helpers/deploy-db';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const APPROVAL_CATALOG = BigNumber.from(1).shl(16);

const PROXY_TYPE = formatBytes32String(EContractId.ApprovalCatalog);

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

    const insuredPoolAddress = Factories.InsuredPoolV1.findInstance(EContractId.InsuredPoolV1);

    if (falsyOrZeroAddress(insuredPoolAddress)) {
      throw new Error(
        `${EContractId.InsuredPoolV1} hasn't been deployed yet. Please, deploy ${EContractId.InsuredPoolV1} first.`
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

    await waitForTx(await proxyCatalog.addAuthenticImplementation(approvalCatalogV1.address, PROXY_TYPE));
    await waitForTx(await proxyCatalog.setDefaultImplementation(approvalCatalogV1.address));

    let approvalCatalogProxyAddress = '';
    const initFunctionData = approvalCatalogV1.interface.encodeFunctionData('initializeApprovalCatalog');

    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxy(deployer.address, PROXY_TYPE, initFunctionData),
      (event) => {
        approvalCatalogProxyAddress = event.proxy;
      }
    );

    console.log(`${EContractId.ApprovalCatalog}:`, approvalCatalogProxyAddress);

    const approvalCatalogProxy = Factories.TransparentProxy.attach(approvalCatalogProxyAddress);
    addProxyToJsonDb(EContractId.ApprovalCatalog, approvalCatalogProxy.address, approvalCatalogV1.address, PROXY_TYPE, [
      deployer.address,
      approvalCatalogV1.address,
      initFunctionData,
    ]);

    await waitForTx(await accessController.setProtection(APPROVAL_CATALOG, false));
    await waitForTx(await accessController.setAddress(APPROVAL_CATALOG, approvalCatalogProxyAddress));
    await waitForTx(await accessController.setProtection(APPROVAL_CATALOG, true));

    console.log(`${EContractId.ApprovalCatalog} was successfully added to ${EContractId.AccessController}`);
  }
);
