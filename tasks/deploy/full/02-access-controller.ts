import { Factories } from '../../../helpers/contract-types';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

deployTask(`full:deploy-access-controller`, `Deploy ${EContractId.AccessController}`, __dirname).setAction(
  async (_, localBRE) => {
    await localBRE.run('set-DRE');

    const existedAccessControllerAddress = Factories.AccessController.findInstance(EContractId.AccessController);

    if (!falsyOrZeroAddress(existedAccessControllerAddress)) {
      console.log(`Already deployed ${EContractId.AccessController}:`, existedAccessControllerAddress);
      return;
    }

    const deployer = await getFirstSigner();
    const accessController = await Factories.AccessController.connectAndDeploy(deployer, EContractId.AccessController, [
      0,
    ]);

    await waitForTx(accessController.deployTransaction);

    console.log(`${EContractId.AccessController}:`, accessController.address);
  }
);
