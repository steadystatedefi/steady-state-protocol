import { formatBytes32String } from 'ethers/lib/utils';

import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { mustWaitTx, notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

const factory = Factories.InsuredPoolV1;

deployTask(`full:deploy-insured-pool`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async () => {
    const proxyCatalog = Factories.ProxyCatalog.get();
    const cc = Factories.CollateralCurrency.get();
    const PROXY_TYPE = formatBytes32String('INSURED_POOL');

    if (notFalsyOrZeroAddress(await proxyCatalog.getDefaultImplementation(PROXY_TYPE, cc.address))) {
      return;
    }

    const [impl] = await getOrDeploy(factory, '', () => {
      const accessController = Factories.AccessController.get();
      return {
        args: [accessController.address, cc.address] as [string, string],
      };
    });

    await mustWaitTx(proxyCatalog.addAuthenticImplementation(impl.address, PROXY_TYPE, cc.address));
    await mustWaitTx(proxyCatalog.setDefaultImplementation(impl.address));

    // let insuredPoolProxyAddress = '';
    // const initFunctionData = insuredPoolV1.interface.encodeFunctionData('initializeInsured', [deployer.address]);
    // await waitForTx(
    //   await proxyCatalog.addAuthenticImplementation(insuredPoolV1.address, PROXY_TYPE, collateralCurrency.address)
    // );
    // await waitForTx(await proxyCatalog.setDefaultImplementation(insuredPoolV1.address));

    // await Events.ProxyCreated.waitOne(
    //   proxyCatalog.createProxy(deployer.address, PROXY_TYPE, collateralCurrency.address, initFunctionData),
    //   (event) => {
    //     insuredPoolProxyAddress = event.proxy;
    //   }
    // );

    // console.log(`${EContractId.InsuredPool}:`, insuredPoolProxyAddress);

    // const insuredPoolProxy = Factories.TransparentProxy.attach(insuredPoolProxyAddress);
    // addProxyToJsonDb(EContractId.InsuredPool, insuredPoolProxy.address, insuredPoolV1.address, PROXY_TYPE, [
    //   deployer.address,
    //   insuredPoolV1.address,
    //   initFunctionData,
    // ]);
  })
);
