import { expect } from 'chai';
import { BigNumber, BigNumberish } from 'ethers';

import { MAX_UINT128, RAY, WAD } from '../../helpers/constants';
import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { MockBalancerLib2 } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Balancer math', (testEnv: TestEnv) => {
  let lib: MockBalancerLib2;
  const t0 = createRandomAddress();
  const t1 = createRandomAddress();
  const t2 = createRandomAddress();

  before(async () => {
    lib = await Factories.MockBalancerLib2.deploy();
  });

  enum StarvationPointMode {
    RateFactor,
    GlobalRateFactor,
    Constant,
    GlobalConstant,
  }

  const starvationPoint = 20;

  const swapTokenStatic = async (
    token: string,
    value: BigNumberish,
    expectedAmount: BigNumberish,
    expectedFee?: BigNumberish,
    minAmount?: number
  ) => {
    const ev = await lib.callStatic.swapToken(token, value, minAmount ?? 0);
    expect(ev.amount).eq(expectedAmount);
    expect(ev.fee).eq(expectedFee ?? BigNumber.from(value).sub(expectedAmount));
  };

  const swapTokenAt = async (
    token: string,
    balance: BigNumberish,
    value: BigNumberish,
    expectedAmount: BigNumberish,
    expectedFee?: BigNumberish,
    minAmount?: number
  ) => {
    await lib.setBalance(token, balance, 0);
    await lib.setTotalBalance(balance, 0);

    await Events.TokenSwapped.waitOneAndUnwrap(
      lib.swapToken(token, value, minAmount ?? 0, { gasLimit: 2000000 }),
      (ev) => {
        expect(ev.amount).eq(expectedAmount);
        expect(ev.fee).eq(expectedFee ?? BigNumber.from(value).sub(expectedAmount));
      }
    );
  };

  it('Starvation point with constant modes', async () => {
    const v = 100;

    await lib.setConfig(t0, WAD, 0, 0, StarvationPointMode.Constant, starvationPoint);
    await swapTokenAt(t0, 100, v, v - starvationPoint / 2);

    await lib.setConfig(t0, WAD, 0, 0, StarvationPointMode.GlobalConstant, 0);
    await swapTokenAt(t0, 100, v, v);
    await lib.setGlobals(0, starvationPoint);
    await swapTokenAt(t0, 100, v, v - starvationPoint / 2);
  });

  it('Starvation point with rate factor mode', async () => {
    const v = 100;
    const rate = 1;

    await lib.setConfig(t0, WAD, 0, starvationPoint, StarvationPointMode.RateFactor, 0);

    const startedAt = await currentTime();
    await lib.setBalance(t0, v, rate);
    await lib.setTotalBalance(v + rate * ((await currentTime()) - startedAt), rate);

    {
      const dV = rate * ((await currentTime()) - startedAt);
      const ev = await Events.TokenSwapped.waitOne(lib.swapToken(t0, v + dV, 0, { gasLimit: 2000000 }));
      if (!testEnv.underCoverage) {
        expect(ev.amount).eq(v + dV - starvationPoint / 2);
      }
    }
  });

  it('Starvation point with global rate factor mode', async () => {
    const v = 100;
    const rate = 1;

    await lib.setConfig(t0, WAD, 0, 0, StarvationPointMode.GlobalRateFactor, 0);
    await lib.setGlobals(starvationPoint, 0);

    const startedAt = await currentTime();
    await lib.setBalance(t0, v, rate);
    await lib.setTotalBalance(v + rate * ((await currentTime()) - startedAt), rate);

    {
      const dV = rate * ((await currentTime()) - startedAt);
      const ev = await Events.TokenSwapped.waitOne(lib.swapToken(t0, v + dV, 0, { gasLimit: 2000000 }));
      if (!testEnv.underCoverage) {
        expect(ev.amount).eq(v + dV - starvationPoint / 2);
      }
    }
  });

  it('Setup assets with different pricing modes', async () => {
    // NB! different tokens are used to test different calculation modes
    // But total will be sync with each token to make it looks like a single asset case

    // price = 1, w = 0 (no fees before starvation)
    await lib.setConfig(t0, WAD, 0, 0, StarvationPointMode.Constant, starvationPoint);

    // price = 1, w = 1 (full fees before starvation)
    await lib.setConfig(t1, WAD, WAD, 0, StarvationPointMode.Constant, starvationPoint);

    // price = 1, w = 1/1000
    await lib.setConfig(t2, WAD, WAD.div(1000), 0, StarvationPointMode.Constant, starvationPoint);
  });

  it('Min limit applied', async () => {
    await swapTokenAt(t0, 100, 10, 0, 0, 20);

    {
      const balance = await lib.getBalance(t0);
      expect(balance.accum).eq(100);
    }
    {
      const balance = await lib.getTotalBalance();
      expect(balance.accum).eq(100);
    }
  });

  const testMinimal = async (v: BigNumberish, r5?: BigNumberish) => {
    if (r5 !== undefined) {
      const at = 5;
      await swapTokenAt(t0, at, v, r5);
      await swapTokenAt(t1, at, v, r5);
      await swapTokenAt(t2, at, v, r5);
    }
    {
      const at = 2;
      await swapTokenAt(t0, at, v, 1);
      await swapTokenAt(t1, at, v, 1);
      await swapTokenAt(t2, at, v, 1);
    }
    {
      const at = 1;
      await swapTokenAt(t0, at, v, 0, 0);
      await swapTokenAt(t1, at, v, 0, 0);
      await swapTokenAt(t2, at, v, 0, 0);
    }
  };

  it('Swap 1', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    const v = 1;
    {
      const at = 100;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 50;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 30;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 20;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 10;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 5;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
  });

  it('Swap 1 @ minimal', async () => {
    await testMinimal(1);
  });

  it('Swap 5', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    const v = 5;
    {
      const at = 100;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 50;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 30;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 20;
      await swapTokenAt(t0, at, v, 4);
      await swapTokenAt(t1, at, v, 4);
      await swapTokenAt(t2, at, v, 4);
    }
    {
      const at = 10;
      await swapTokenAt(t0, at, v, 2);
      await swapTokenAt(t1, at, v, 2);
      await swapTokenAt(t2, at, v, 2);
    }

    await testMinimal(v, 1);
  });

  it('Swap 10', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    const v = 10;
    {
      const at = 100;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, v);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 50;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, 9);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 30;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, 8);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 20;
      await swapTokenAt(t0, at, v, 7);
      await swapTokenAt(t1, at, v, 7);
      await swapTokenAt(t2, at, v, 7);
    }
    {
      const at = 10;
      await swapTokenAt(t0, at, v, 2);
      await swapTokenAt(t1, at, v, 2);
      await swapTokenAt(t2, at, v, 2);
    }

    await testMinimal(v, 1);
  });

  it('Swap 50', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    const v = 50;
    {
      const at = 1000;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, 48);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 100;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, 34);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 50;
      await swapTokenAt(t0, at, v, at - starvationPoint / 2);
      await swapTokenAt(t1, at, v, at / 2);
      await swapTokenAt(t2, at, v, 31);
    }
    {
      const at = 30;
      await swapTokenAt(t0, at, v, 24);
      await swapTokenAt(t1, at, v, 19);
      await swapTokenAt(t2, at, v, 11);
    }
    {
      const at = 20;
      await swapTokenAt(t0, at, v, 15);
      await swapTokenAt(t1, at, v, 15);
      await swapTokenAt(t2, at, v, 15);
    }
    {
      const at = 10;
      await swapTokenAt(t0, at, v, 6);
      await swapTokenAt(t1, at, v, 6);
      await swapTokenAt(t2, at, v, 6);
    }

    await testMinimal(v, 2);
  });

  it('Swap 100', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    const v = 100;
    {
      const at = 1000;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, 91);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 100;
      await swapTokenAt(t0, at, v, at - starvationPoint / 2);
      await swapTokenAt(t1, at, v, at / 2);
      await swapTokenAt(t2, at, v, 81);
    }
    {
      const at = 50;
      await swapTokenAt(t0, at, v, 46);
      await swapTokenAt(t1, at, v, 34);
      await swapTokenAt(t2, at, v, 31);
    }
    {
      const at = 30;
      await swapTokenAt(t0, at, v, 27);
      await swapTokenAt(t1, at, v, 24);
      await swapTokenAt(t2, at, v, 11);
    }
    {
      const at = 20;
      await swapTokenAt(t0, at, v, 17);
      await swapTokenAt(t1, at, v, 17);
      await swapTokenAt(t2, at, v, 17);
    }
    {
      const at = 10;
      await swapTokenAt(t0, at, v, 8);
      await swapTokenAt(t1, at, v, 8);
      await swapTokenAt(t2, at, v, 8);
    }

    await testMinimal(v, 3);
  });

  it('Swap 1000', async () => {
    const v = 1000;
    {
      const at = 10000;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, 910);
      await swapTokenAt(t2, at, v, v);
    }
    {
      const at = 1000;
      await swapTokenAt(t0, at, v, at - starvationPoint / 2);
      await swapTokenAt(t1, at, v, at / 2);
      await swapTokenAt(t2, at, v, 981);
    }
    {
      const at = 100;
      await swapTokenAt(t0, at, v, 99);
      await swapTokenAt(t1, at, v, 91);
      await swapTokenAt(t2, at, v, 81);
    }

    if (testEnv.underCoverage) {
      return;
    }

    {
      const at = 50;
      await swapTokenAt(t0, at, v, 49);
      await swapTokenAt(t1, at, v, 48);
      await swapTokenAt(t2, at, v, 31);
    }
    {
      const at = 30;
      await swapTokenAt(t0, at, v, 29);
      await swapTokenAt(t1, at, v, 29);
      await swapTokenAt(t2, at, v, 11);
    }
    {
      const at = 20;
      await swapTokenAt(t0, at, v, 19);
      await swapTokenAt(t1, at, v, 19);
      await swapTokenAt(t2, at, v, 19);
    }
    {
      const at = 10;
      await swapTokenAt(t0, at, v, 9);
      await swapTokenAt(t1, at, v, 9);
      await swapTokenAt(t2, at, v, 9);
    }

    await testMinimal(v, 4);
  });

  it('Swap extremes', async () => {
    const t3 = createRandomAddress();

    // price = 1, w = 1/WAD
    await lib.setConfig(t3, WAD, 1, 0, StarvationPointMode.Constant, 20);

    const v = RAY;
    {
      // This value allows to use the smallest possible w (fee control) when swapping 1e9 wads.
      const at = BigNumber.from(2).pow(106);

      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, '999987674200283132975237507');
      await swapTokenAt(t2, at, v, '999999987674048507850772600');
      await swapTokenAt(t3, at, v, '999999999999999999999987675');
    }

    if (testEnv.underCoverage) {
      return;
    }

    {
      const at = MAX_UINT128;
      await swapTokenAt(t0, at, v, v);
      await swapTokenAt(t1, at, v, '999999999997061264122952918');
      await swapTokenAt(t2, at, v, '999999999999997061264122945');

      // NB! It is possible to reduce precision and allow this corner-case to be supported, but this combination of params is mythical
      await expect(swapTokenAt(t3, at, v, v)).revertedWith('Arithmetic operation underflowed or overflowed');
    }
    {
      const at = RAY;
      await swapTokenAt(t0, at, v, at.sub(starvationPoint / 2));
      await swapTokenAt(t1, at, v, at.div(2));
      await swapTokenAt(t2, at, v, '999000999000999000999001000');
      await swapTokenAt(t3, at, v, '999999999999999999000000001');
    }
    {
      const at = WAD;
      await swapTokenAt(t0, at, v, at.sub(1));
      await swapTokenAt(t1, at, v, '999999999000000001');
      await swapTokenAt(t2, at, v, at.sub(1));
      await swapTokenAt(t3, at, v, '999999999999999981');
    }

    await testMinimal(v);

    await testMinimal(MAX_UINT128);
  });

  it('Smooth curve transition at the starvation point', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    /*
    NB! This test only applies to the flattened curve mode (0 < w < 1) and checks that 
    the switch between function at the starvation point is smooth and creates no dent / step.
    */

    const t3 = createRandomAddress();

    // A large enough value for proper precision
    const sPoint = WAD;

    await lib.setConfig(t3, WAD, WAD.div(1000), 0, StarvationPointMode.Constant, sPoint);

    await lib.setBalance(t3, sPoint.mul(2), 0);
    await lib.setTotalBalance(sPoint.mul(2), 0);

    // 1000500250125062531 => 1000000000000000000
    const v = BigNumber.from('1000500250125062530');
    for (let i = 0; i <= 2; i++) {
      const ev = await lib.callStatic.swapToken(t3, v.add(i), 0);
      expect(ev.amount).eq(sPoint.sub(1).add(i));
    }
  });

  it('Fees and cross-weighted swaps', async () => {
    if (testEnv.underCoverage) {
      return;
    }

    // use large base to simplify the test - it will diminish the impact of (rate*time)
    const base = WAD;
    await lib.setTotalBalance(base.mul(4), 4);

    // the relative balance == to the relative rate
    await lib.setBalance(t0, base.mul(1), 1);
    await swapTokenStatic(t0, 10, 10, 0);

    // the relative balance > the relative rate => this asset is in excess, give more of the asset for the same value
    await lib.setBalance(t0, base.mul(2), 1);
    await swapTokenStatic(t0, 10, 20, 0);

    // the relative balance < the relative rate => this asset is in demand, give less of the asset for the same value
    await lib.setBalance(t0, base.mul(1), 2);
    await swapTokenStatic(t0, 10, 5, 0); // all fees are retained for balancing

    await swapTokenStatic(t0, WAD.mul(2), WAD.sub(starvationPoint / 2), WAD.add(starvationPoint / 2).div(2));
    await swapTokenStatic(t0, WAD, WAD.div(2).sub(1), '107142857142857145');
  });
});
