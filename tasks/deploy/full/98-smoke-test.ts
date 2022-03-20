import { task } from 'hardhat/config';
import { ConfigNames, loadRuntimeConfig } from '../../../helpers/config-loader';
import { eNetwork } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

task(`full:smoke-test`, 'Smoke test')
  .addParam('cfg', `Configuration name: ${Object.values(ConfigNames)}`)
  .setAction(async ({ cfg }, localBRE) => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
