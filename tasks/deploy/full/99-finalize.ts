import { task } from 'hardhat/config';

import { NamesOfConfig } from '../../../helpers/config-loader';

task(`full:deploy-finalize`, 'Finalize deploy')
  .addParam('cfg', `Configuration name: ${NamesOfConfig}`)
  .addFlag('register', `Register access controller`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
