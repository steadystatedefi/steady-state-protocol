import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addProxyToJsonDb } from '../../../helpers/deploy-db';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const PROXY_TYPE = formatBytes32String('INSURED_POOL');

deployTask(`full:deploy-insured-pool`, `Deploy ${EContractId.InsuredPoolV2}`, __dirname).setAction(
  async (_, localBRE) => {
    await localBRE.run('set-DRE');

    const existedInsuredPoolV2Address = Factories.InsuredPoolV2.findInstance(EContractId.InsuredPoolV2);

    if (!falsyOrZeroAddress(existedInsuredPoolV2Address)) {
      console.log(`Already deployed ${EContractId.InsuredPoolV2}:`, existedInsuredPoolV2Address);
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

    const insuredPoolV2 = await Factories.InsuredPoolV2.connectAndDeploy(deployer, EContractId.InsuredPoolV2, [
      accessController.address,
      collateralCurrency.address,
    ]);
    await waitForTx(insuredPoolV2.deployTransaction);

    console.log(`${EContractId.InsuredPoolV2}:`, insuredPoolV2.address);

    let insuredPoolProxyAddress = '';
    const initFunctionData = insuredPoolV2.interface.encodeFunctionData('initializeInsured', [deployer.address]);
    await waitForTx(await proxyCatalog.addAuthenticImplementation(insuredPoolV2.address, PROXY_TYPE));
    await waitForTx(await proxyCatalog.setDefaultImplementation(insuredPoolV2.address));

    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxy(deployer.address, PROXY_TYPE, initFunctionData),
      (event) => {
        insuredPoolProxyAddress = event.proxy;
      }
    );

    console.log(`${EContractId.InsuredPool}:`, insuredPoolProxyAddress);

    const insuredPoolProxy = Factories.TransparentProxy.attach(insuredPoolProxyAddress);
    addProxyToJsonDb(EContractId.InsuredPool, insuredPoolProxy.address, insuredPoolV2.address, PROXY_TYPE, [
      deployer.address,
      insuredPoolV2.address,
      initFunctionData,
    ]);
  }
);
