import { expect } from 'chai';

import { WAD } from '../../helpers/constants';
import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress } from '../../helpers/runtime-utils';
import { MockBalancerLib2 } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Balancer math', (testEnv: TestEnv) => {
  let lib: MockBalancerLib2;
  const t0 = createRandomAddress();

  before(async () => {
    lib = await Factories.MockBalancerLib2.deploy();
  });

  it('Zero balance', async () => {
    await lib.setTotalBalance(1000, 1);
    await lib.setConfig(t0, WAD, WAD, 10);
    await lib.setBalance(t0, 100, 1);

    await Events.TokenSwapped.waitOneAndUnwrap(lib.swapToken(t0, 10, 0), (ev) => {
      console.log(ev);
    });
  });
});
