import { loadRuntimeConfig, ConfigNames } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { falsyOrZeroAddress, getSigners, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const CONTRACT_NAME = 'AccessController';

deployTask(`full:deploy-access-controller`, `Deploy ${CONTRACT_NAME}`, __dirname).setAction(
  async ({ cfg }, localBRE) => {
    await localBRE.run('set-DRE');

    const { AccessController } = loadRuntimeConfig(cfg as ConfigNames);
    const [deployer] = await getSigners();

    const existedAccessControllerAddress = Factories.AccessController.findInstance(EContractId.AccessController);

    if (!falsyOrZeroAddress(existedAccessControllerAddress)) {
      console.log(`Already deployed ${CONTRACT_NAME}:`, existedAccessControllerAddress);
      return;
    }

    const accessController = await Factories.AccessController.connectAndDeploy(deployer, EContractId.AccessController, [
      AccessController.SINGLETS,
      AccessController.ROLES,
      AccessController.PROTECTED_SINGLETS,
    ]);

    await waitForTx(accessController.deployTransaction);

    console.log(`${CONTRACT_NAME}:`, accessController.address);
  }
);
