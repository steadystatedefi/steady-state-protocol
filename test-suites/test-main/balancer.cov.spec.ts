import { expect } from 'chai';
import { BigNumberish } from 'ethers';

import { RAY, WAD } from '../../helpers/constants';
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

  const swapToken = async (
    token: string,
    value: BigNumberish,
    minAmount: number,
    expectedAmount: number,
    expectedFee: BigNumberish
  ) => {
    await Events.TokenSwapped.waitOneAndUnwrap(lib.swapToken(token, value, minAmount, { gasLimit: 1000000 }), (ev) => {
      expect(ev.amount).eq(expectedAmount);
      expect(ev.fee).eq(expectedFee);
    });
  };

  enum StarvationPointMode {
    RateFactor,
    GlobalRateFactor,
    Constant,
    GlobalConstant,
  }

  it('Flat pricing, one asset', async () => {
    // price = 1, w = 0 (no fees before starvation)
    await lib.setConfig(t0, WAD, 0, 0, StarvationPointMode.Constant, 20);

    // total = 100, rate = 0
    await lib.setTotalBalance(100, 0);
    await lib.setBalance(t0, 100, 0);
  });

  it('Min limit applied', async () => {
    await swapToken(t0, 10, 20, 0, 0);

    {
      const balance = await lib.getBalance(t0);
      expect(balance.accum).eq(100);
    }
    {
      const balance = await lib.getTotalBalance();
      expect(balance.accum).eq(100);
    }
  });

  it('Swap 10 @ 100 -> 10 (flat and above the starvation point)', async () => {
    await swapToken(t0, 10, 0, 10, 0);

    {
      const balance = await lib.getBalance(t0);
      expect(balance.accum).eq(90);
    }
    {
      const balance = await lib.getTotalBalance();
      expect(balance.accum).eq(90);
    }
  });

  it('Swap 70 @ 90 -> 70 (flat and above the starvation point)', async () => {
    await swapToken(t0, 70, 70, 70, 0);
  });

  it('Swap 20 @ 20 -> 10 (below the starvation point, constant product applied)', async () => {
    // Constant product in action: we swap 20 value points for 10 asset points only. The rest is takes as fees.
    await swapToken(t0, 20, 0, 10, 10);
  });

  it('Swap 100 @ 100 -> 90 (flat and cross the starvation point)', async () => {
    // Reset balances
    // total = 100, rate = 0
    await lib.setTotalBalance(100, 0);
    await lib.setBalance(t0, 100, 0);

    await swapToken(t0, 100, 0, 90, 10);
  });

  it('Curve pricing, one asset', async () => {
    // price = 1, w = 1 (full fees before starvation)
    await lib.setConfig(t0, WAD, WAD, 0, StarvationPointMode.Constant, 20);

    // total = 100, rate = 0
    await lib.setTotalBalance(100, 0);
    await lib.setBalance(t0, 100, 0);
  });

  it('Swap 10 @ 100 -> 9 (curved, above the starvation point)', async () => {
    await swapToken(t0, 10, 0, 9, 1);
  });

  it('Swap 1 @ 91 -> 1 (curved, above the starvation point)', async () => {
    await swapToken(t0, 1, 0, 1, 0);
  });

  it('Swap 50 @ 90 -> 32 (curved, above the starvation point)', async () => {
    await swapToken(t0, 50, 0, 32, 18);
  });

  it('Swap 25 @ 58 -> 17 (curved, above the starvation point)', async () => {
    await swapToken(t0, 25, 0, 17, 8);
  });

  it('Swap 25 @ 41 -> 16 (curved, above the starvation point)', async () => {
    await swapToken(t0, 25, 0, 16, 9);
  });

  it('(5x) Swap 1 @ 25..21 -> 1 (curved, above the starvation point)', async () => {
    await swapToken(t0, 1, 0, 1, 0);
    await swapToken(t0, 1, 0, 1, 0);
    await swapToken(t0, 1, 0, 1, 0);
    await swapToken(t0, 1, 0, 1, 0);
    await swapToken(t0, 1, 0, 1, 0);
  });

  it('Swap 25 @ 20 -> 11 (curved, below the starvation point)', async () => {
    await swapToken(t0, 25, 0, 11, 14);
  });

  it('Swap 25 @ 9 -> 3 (curved, below the starvation point)', async () => {
    await swapToken(t0, 25, 0, 3, 22);
  });

  it('Swap 25 @ 6 -> 2 (curved, below the starvation point)', async () => {
    await swapToken(t0, 25, 0, 2, 23);
  });

  it('Swap 25 @ 4 -> 1 (curved, below the starvation point)', async () => {
    await swapToken(t0, 25, 0, 1, 24);
  });

  it('Swap 25 @ 3 -> 0 (curved, below the starvation point)', async () => {
    await swapToken(t0, 25, 0, 0, 0);
  });

  it('Swap 1e18 @ 3 -> 2 (curved, below the starvation point)', async () => {
    await swapToken(t0, WAD, 0, 2, WAD.sub(2));
  });

  it('Swap 1e45 @ 1 -> 0 (curved, below the starvation point)', async () => {
    await swapToken(t0, RAY.mul(WAD), 0, 0, 0);
  });

  it('Swap 3000 @ 100 -> 90 (curved and cross the starvation point)', async () => {
    // Reset balances
    // total = 100, rate = 0
    await lib.setTotalBalance(100, 0);
    await lib.setBalance(t0, 100, 0);

    await swapToken(t0, 3000, 0, 90, 2910);
  });
});
