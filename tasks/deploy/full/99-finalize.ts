import { task } from 'hardhat/config';

import { configNameParams } from '../../../helpers/config-loader';

task(`full:deploy-finalize`, 'Finalize deploy')
  .addParam('cfg', `Configuration name: ${configNameParams}`)
  .addFlag('register', `Register access controller`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
