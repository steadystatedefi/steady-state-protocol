import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { mustWaitTx, notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

const factory = Factories.FrontHelper;

deployTask(`full:deploy-front-helper`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async () => {
    const accessController = Factories.AccessController.get();
    const accessFlag = AccessFlags.DATA_HELPER;

    const found = await accessController.getAddress(accessFlag);
    if (notFalsyOrZeroAddress(found)) {
      console.log(`Already deployed: ${found}`);
      return;
    }

    const [fh] = await getOrDeploy(factory, '', () => ({ args: [accessController.address] as [string] }));

    await mustWaitTx(accessController.setAddress(accessFlag, fh.address));
  })
);
