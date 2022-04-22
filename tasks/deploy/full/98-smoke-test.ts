import { task } from 'hardhat/config';

import { configNameParams } from '../../../helpers/config-loader';

task(`full:smoke-test`, 'Smoke test')
  .addParam('cfg', `Configuration name: ${configNameParams}`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
