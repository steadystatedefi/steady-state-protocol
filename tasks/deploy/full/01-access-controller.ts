import { BigNumberish } from 'ethers';

import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getDefaultDeployer, getOrDeploy } from '../../../helpers/factory-wrapper';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

const factory = Factories.AccessController;

deployTask(`full:deploy-access-controller`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async () => {
    const [ac] = await getOrDeploy(factory, '', () => ({ args: [0] as [BigNumberish] }));
    await mustWaitTx(ac.setAnyRoleMode(false));

    const deployer = getDefaultDeployer();
    await mustWaitTx(ac.setTemporaryAdmin(deployer.address, 3600));

    await mustWaitTx(ac.grantRoles(deployer.address, AccessFlags.LP_DEPLOY));
  })
);
