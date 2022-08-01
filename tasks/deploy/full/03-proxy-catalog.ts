import { BigNumber } from 'ethers';

import { Factories } from '../../../helpers/contract-types';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const PROXY_FACTORY = BigNumber.from(1).shl(26);

deployTask(`full:deploy-proxy-catalog`, `Deploy ${EContractId.ProxyCatalog}`, __dirname).setAction(
  async (_, localBRE) => {
    await localBRE.run('set-DRE');

    const existedProxyCatalogAddress = Factories.ProxyCatalog.findInstance(EContractId.ProxyCatalog);

    if (!falsyOrZeroAddress(existedProxyCatalogAddress)) {
      console.log(`Already deployed ${EContractId.ProxyCatalog}:`, existedProxyCatalogAddress);
      return;
    }

    const accessControllerAddress = Factories.AccessController.findInstance(EContractId.AccessController);

    if (falsyOrZeroAddress(accessControllerAddress)) {
      throw new Error(
        `${EContractId.AccessController} hasn't been deployed yet. Please, deploy ${EContractId.AccessController} first.`
      );
    }

    const deployer = await getFirstSigner();
    const accessController = Factories.AccessController.get(deployer, EContractId.AccessController);

    const proxyCatalog = await Factories.ProxyCatalog.connectAndDeploy(deployer, EContractId.ProxyCatalog, [
      accessController.address,
    ]);
    await waitForTx(proxyCatalog.deployTransaction);

    console.log(`${EContractId.ProxyCatalog}:`, proxyCatalog.address);

    await waitForTx(await accessController.setAddress(PROXY_FACTORY, proxyCatalog.address));

    console.log(`${EContractId.ProxyCatalog} was successfully added to ${EContractId.AccessController}`);
  }
);
