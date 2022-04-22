import { task } from 'hardhat/config';

import { ConfigNames } from '../../../helpers/config-loader';

task(`full:access-test`, 'Smoke test')
  .addParam('cfg', `Configuration name: ${JSON.stringify(Object.values(ConfigNames))}`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
  });
