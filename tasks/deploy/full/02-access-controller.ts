import { MAX_UINT } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { falsyOrZeroAddress, getSigners, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const CONTRACT_NAME = 'AccessController';

const ROLES = MAX_UINT.mask(16);
const SINGLETS = MAX_UINT.mask(64).xor(ROLES);
const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES);

deployTask(`full:deploy-access-controller`, `Deploy ${CONTRACT_NAME}`, __dirname).setAction(async (_, localBRE) => {
  await localBRE.run('set-DRE');

  const [deployer] = await getSigners();

  const existedAccessControllerAddress = Factories.AccessController.findInstance(EContractId.AccessController);

  if (!falsyOrZeroAddress(existedAccessControllerAddress)) {
    console.log(`Already deployed ${CONTRACT_NAME}:`, existedAccessControllerAddress);
    return;
  }

  const accessController = await Factories.AccessController.connectAndDeploy(deployer, EContractId.AccessController, [
    SINGLETS,
    ROLES,
    PROTECTED_SINGLETS,
  ]);

  await waitForTx(accessController.deployTransaction);

  console.log(`${CONTRACT_NAME}:`, accessController.address);
});
