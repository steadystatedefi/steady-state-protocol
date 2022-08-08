import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addProxyToJsonDb } from '../../../helpers/deploy-db';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const PROXY_TYPE = formatBytes32String('INSURED_POOL');

deployTask(`full:deploy-insured-pool`, `Deploy ${EContractId.InsuredPoolV1}`, __dirname).setAction(
  async (_, localBRE) => {
    await localBRE.run('set-DRE');

    const existedInsuredPoolV1Address = Factories.InsuredPoolV1.findInstance(EContractId.InsuredPoolV1);

    if (!falsyOrZeroAddress(existedInsuredPoolV1Address)) {
      console.log(`Already deployed ${EContractId.InsuredPoolV1}:`, existedInsuredPoolV1Address);
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

    const collateralCurrencyTokenAddress = Factories.CollateralCurrency.findInstance(EContractId.CollateralCurrency);

    if (falsyOrZeroAddress(collateralCurrencyTokenAddress)) {
      throw new Error(
        `${EContractId.CollateralCurrency} hasn't been deployed yet. Please, deploy ${EContractId.CollateralCurrency} first.`
      );
    }

    const deployer = await getFirstSigner();
    const proxyCatalog = Factories.ProxyCatalog.get(deployer, EContractId.ProxyCatalog);
    const accessController = Factories.AccessController.get(deployer, EContractId.AccessController);
    const collateralCurrency = Factories.MockERC20.get(deployer, EContractId.CollateralCurrency);

    const insuredPoolV1 = await Factories.InsuredPoolV1.connectAndDeploy(deployer, EContractId.InsuredPoolV1, [
      accessController.address,
      collateralCurrency.address,
    ]);
    await waitForTx(insuredPoolV1.deployTransaction);

    console.log(`${EContractId.InsuredPoolV1}:`, insuredPoolV1.address);

    let insuredPoolProxyAddress = '';
    const initFunctionData = insuredPoolV1.interface.encodeFunctionData('initializeInsured', [deployer.address]);
    await waitForTx(await proxyCatalog.addAuthenticImplementation(insuredPoolV1.address, PROXY_TYPE));
    await waitForTx(await proxyCatalog.setDefaultImplementation(insuredPoolV1.address));

    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxy(deployer.address, PROXY_TYPE, initFunctionData),
      (event) => {
        insuredPoolProxyAddress = event.proxy;
      }
    );

    console.log(`${EContractId.InsuredPool}:`, insuredPoolProxyAddress);

    const insuredPoolProxy = Factories.TransparentProxy.attach(insuredPoolProxyAddress);
    addProxyToJsonDb(EContractId.InsuredPool, insuredPoolProxy.address, insuredPoolV1.address, PROXY_TYPE, [
      deployer.address,
      insuredPoolV1.address,
      initFunctionData,
    ]);
  }
);
