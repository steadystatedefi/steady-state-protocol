import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { deployTask } from '../deploy-steps';
import { assignRole } from '../templates';

const factory = Factories.FrontHelper;

deployTask(`full:deploy-front-helper`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async () => {
    const accessController = Factories.AccessController.get();

    const [fh, newDeploy] = await getOrDeploy(factory, '', [accessController.address]);

    await assignRole(AccessFlags.DATA_HELPER, fh.address, newDeploy, accessController);
  })
);
