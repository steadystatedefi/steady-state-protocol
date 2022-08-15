import { task } from 'hardhat/config';

import { ConfigNamesAsString } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { falsyOrZeroAddress, mustWaitTx } from '../../../helpers/runtime-utils';

task(`full:deploy-finalize`, 'Finalize deploy')
  .addParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
  .addFlag('register', `Register access controller`)
  .setAction(
    dreAction(async () => {
      const acAddr = Factories.AccessController.findInstance() ?? '';
      if (falsyOrZeroAddress(acAddr)) {
        return;
      }

      const ac = Factories.AccessController.attach(acAddr);
      console.log('Renounce temporary admin');
      await mustWaitTx(ac.renounceTemporaryAdmin());
    })
  );
