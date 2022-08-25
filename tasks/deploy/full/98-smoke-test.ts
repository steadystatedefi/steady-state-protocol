import { task } from 'hardhat/config';

import { ConfigNamesAsString } from '../../../helpers/config-loader';
import { dreAction } from '../../../helpers/dre';

task(`full:smoke-test`, 'Smoke test')
  .addOptionalParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
  .setAction(
    dreAction(async () => {
      // await localBRE.run('set-DRE');
      // const network = <eNetwork>localBRE.network.name;
      // const poolConfig = loadRuntimeConfig(pool);
    })
  );
