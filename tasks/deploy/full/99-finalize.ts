import { task } from 'hardhat/config';

import { NamesOfConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { falsyOrZeroAddress, mustWaitTx } from '../../../helpers/runtime-utils';

task(`full:deploy-finalize`, 'Finalize deploy')
  .addParam('cfg', `Configuration name: ${NamesOfConfig}`)
  .addFlag('register', `Register access controller`)
  .setAction(
    dreAction(async () => {
      // const network = <eNetwork>localBRE.network.name;
      // const poolConfig = loadRuntimeConfig(pool);
      const acAddr = Factories.AccessController.findInstance() ?? '';
      if (falsyOrZeroAddress(acAddr)) {
        return;
      }

      const ac = Factories.AccessController.attach(acAddr);
      await mustWaitTx(ac.renounceTemporaryAdmin());
    })
  );
