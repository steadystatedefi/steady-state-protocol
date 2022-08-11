import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { MAX_UINT } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { waitForTx } from '../../../helpers/runtime-utils';
import { ProxyCatalog } from '../../../types';
import { deployTask } from '../deploy-steps';

const factory = Factories.ProxyCatalog;

deployTask(`full:deploy-proxy-catalog`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(() =>
    getOrDeploy(factory, '', () => {
      const accessController = Factories.AccessController.get();

      return {
        args: [accessController.address] as [string],
        post: async (proxyCatalog: ProxyCatalog) => {
          await waitForTx(await proxyCatalog.setAccess([formatBytes32String('INSURED_POOL')], [MAX_UINT]));
          await waitForTx(await accessController.setAddress(AccessFlags.PROXY_FACTORY, proxyCatalog.address));
        },
      };
    })
  )
);
