import { task } from 'hardhat/config';

import { ConfigNamesAsString } from '../../../helpers/config-loader';

task(`full:smoke-test`, 'Smoke test')
  .addParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
