import { ENetwork } from '../config-networks';
import { IConfiguration } from '../config-types';

import { FullConfig } from './full';

export const DevConfig: IConfiguration<ENetwork> = {
  main: FullConfig.main,
  hardhat: FullConfig.main,
};
