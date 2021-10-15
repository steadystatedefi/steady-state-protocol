import { task } from 'hardhat/config';
import { ConfigNames } from '../../../helpers/config_loader';

task(`full:deploy-finalize`, 'Finalize deploy')
  .addParam('cfg', `Configuration name: ${Object.values(ConfigNames)}`)
  .addFlag('register', `Register access controller`)
  .setAction(async ({ cfg, register }, localBRE) => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
