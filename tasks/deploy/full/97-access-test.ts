import { task } from 'hardhat/config';

import { NamesOfConfig } from '../../../helpers/config-loader';

task(`full:access-test`, 'Smoke test')
  .addParam('cfg', `Configuration name: ${NamesOfConfig}`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
