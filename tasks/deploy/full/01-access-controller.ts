import { isZeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getDefaultDeployer, getOrDeploy } from '../../../helpers/factory-wrapper';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

const factory = Factories.AccessController;

deployTask(`full:deploy-access-controller`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);
    const [ac, newDeploy] = await getOrDeploy(factory, '', [0]);
    await mustWaitTx(ac.setAnyRoleMode(false));

    const deployer = getDefaultDeployer();
    if (newDeploy || deployer.address !== (await ac.getTemporaryAdmin()).admin) {
      console.log('Grant temporary admin:', deployer.address);
      await mustWaitTx(ac.setTemporaryAdmin(deployer.address, 3600));
      await mustWaitTx(
        ac.grantRoles(
          deployer.address,
          AccessFlags.LP_DEPLOY + AccessFlags.INSURER_ADMIN + AccessFlags.PRICE_ROUTER_ADMIN
        )
      );
    }

    if (cfg.Owner) {
      const newOwner = cfg.Owner.toUpperCase();
      if (newOwner === deployer.address.toUpperCase()) {
        console.log('Deployer is owner');
      } else {
        const currentOwners = await ac.owners();
        if (
          newOwner === currentOwners.activeOwner.toUpperCase() ||
          newOwner === currentOwners.pendingOwner.toUpperCase()
        ) {
          console.log('Owner is already assigned/pending:', cfg.Owner);
        } else if (deployer.address.toUpperCase() !== currentOwners.activeOwner.toUpperCase()) {
          throw new Error(
            `Deployer is not an owner: ${deployer.address}, ${currentOwners.activeOwner}, ${currentOwners.pendingOwner}`
          );
        } else if (isZeroAddress(newOwner)) {
          console.log('Renouncing ownership');
          await mustWaitTx(ac.renounceOwnership());
          await mustWaitTx(ac.acceptOwnershipTransfer());
        } else {
          console.log('Transferring ownership:', cfg.Owner);
          await mustWaitTx(ac.transferOwnership(newOwner));
        }
      }
    }

    for (const ea of cfg.EmergencyAdmins ?? []) {
      if (!(await ac.isAddress(AccessFlags.EMERGENCY_ADMIN, ea))) {
        console.log('Grant EMERGENCY_ADMIN:', ea);
        await mustWaitTx(ac.grantRoles(ea, AccessFlags.EMERGENCY_ADMIN));
      }
    }
  })
);
