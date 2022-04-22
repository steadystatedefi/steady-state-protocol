/* eslint-disable */
// TODO: enable later
import { task } from 'hardhat/config';
import { ConfigNames, loadRuntimeConfig } from '../../../helpers/config-loader';

task(`full:access-test`, 'Smoke test')
  .addParam('cfg', `Configuration name: ${Object.values(ConfigNames)}`)
  .setAction(async ({ cfg }, localBRE) => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
