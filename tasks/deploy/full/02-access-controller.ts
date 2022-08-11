import { BigNumberish } from 'ethers';

import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { deployTask } from '../deploy-steps';

const factory = Factories.AccessController;

deployTask(`full:deploy-access-controller`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(() => getOrDeploy(factory, '', () => ({ args: [0] as [BigNumberish] })))
);
