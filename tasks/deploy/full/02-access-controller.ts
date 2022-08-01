import { MAX_UINT } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const ROLES = MAX_UINT.mask(16);
const SINGLETS = MAX_UINT.mask(64).xor(ROLES);
const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES);

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
      SINGLETS.toString(),
      ROLES.toString(),
      PROTECTED_SINGLETS.toString(),
    ]);

    await waitForTx(accessController.deployTransaction);

    console.log(`${EContractId.AccessController}:`, accessController.address);
  }
);
