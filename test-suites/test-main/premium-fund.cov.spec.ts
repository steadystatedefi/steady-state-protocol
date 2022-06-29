import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';

// import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { advanceTimeAndBlock, currentTime } from '../../helpers/runtime-utils';
import {
  CollateralCurrency,
  MockPremiumActuary,
  MockPremiumSource,
  MockPremiumFund,
  MockERC20,
  PremiumFund,
} from '../../types';

import { makeSharedStateSuite, makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Premium Fund', (testEnv: TestEnv) => {
  let fund: MockPremiumFund;
  let actuary: MockPremiumActuary;
  const sources: MockPremiumSource[] = []; // todo: mapping of tokens => sources
  let token2Source: MockPremiumSource;
  let cc: CollateralCurrency;
  let token1: MockERC20;
  let token2: MockERC20;
  let user: SignerWithAddress;

  let numSources;

  const createPremiumSource = async (premiumToken: string) => {
    const source = await Factories.MockPremiumSource.deploy(premiumToken, cc.address);
    sources.push(source);
  };

  enum StarvationPointMode {
    RateFactor = 0 + 64, // + BF_AUTO_REPLENISH
    GlobalRateFactor = 1 + 64, // + BF_AUTO_REPLENISH
    Constant = 2,
    GlobalConstant = 3,
  }

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.CollateralCurrency.deploy('Collateral', '$CC', 18);
    fund = await Factories.MockPremiumFund.deploy(cc.address);
    actuary = await Factories.MockPremiumActuary.deploy(fund.address, cc.address);

    token1 = await Factories.MockERC20.deploy('Mock token1', 'MCK', 18);
    token2 = await Factories.MockERC20.deploy('Mock token2', 'MCK2', 18);
    numSources = 5;

    for (let i = 0; i < numSources; i++) {
      await createPremiumSource(token1.address);
      await token1.mint(
        sources[i].address,
        BigNumber.from(10)
          .pow(18)
          .mul((i + 1) * 100)
      );
    }

    token2Source = await Factories.MockPremiumSource.deploy(token2.address, cc.address);
    await token2.mint(token2Source.address, BigNumber.from(10).pow(18).mul(100));

    await fund.setDefaultConfig(
      actuary.address,
      0,
      // BigNumber.from(10).pow(18),
      0,
      0,
      StarvationPointMode.Constant,
      20
    );
  });

  const setupTestEnv = async (rates: BigNumber[], token2rate: BigNumber) => {
    await fund.registerPremiumActuary(actuary.address, true);
    await fund.setPrice(token1.address, BigNumber.from(10).pow(18));
    await fund.setPrice(token2.address, BigNumber.from(10).pow(17).mul(5));

    if (rates.length !== numSources) {
      throw Error('Incorrect rates length');
    }

    for (let i = 0; i < numSources; i++) {
      await actuary.addSource(sources[i].address);
      await actuary.setRate(sources[i].address, rates[i]);
    }

    await actuary.addSource(token2Source.address);
    await actuary.setRate(token2Source.address, token2rate);
  };

  const sourceTokenBalances = async (token: MockERC20) => {
    const balances: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      balances.push(await token.balanceOf(sources[i].address));
    }

    return balances;
  };

  const timeDiff = async (earlier: number) => (await currentTime()) - earlier;

  // When increment is set for premiumAllocationUpdated
  // it is a certain amount asked by the actuary
  const requestPremiumAmount = async (index: number, increment: BigNumber) => {
    await actuary.callPremiumAllocationUpdated(sources[index].address, 0, increment, 0);
  };

  it('Register actuary and premium sources', async () => {
    // Must add actuary before adding source
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;
    await fund.registerPremiumActuary(actuary.address, true);
    await actuary.addSource(sources[0].address);
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;

    await fund.setPrice(token1.address, BigNumber.from(10).pow(18));

    // Must set rate before syncing
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await actuary.setRate(sources[0].address, 10);
    await fund.syncAsset(actuary.address, 0, token1.address);

    // Can't sync while token1 is paused
    await fund.setPausedToken(token1.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await fund.setPausedToken(token1.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address);

    // Can't sync or swap while actuary is paused
    await fund['setPaused(address,bool)'](actuary.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await expect(fund.swapAsset(actuary.address, user.address, user.address, 10, token1.address, 9)).to.be.reverted;
    await fund['setPaused(address,bool)'](actuary.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address);

    await actuary.removeSource(sources[0].address);
    await fund.registerPremiumActuary(actuary.address, false);
  });

  it('Test rates', async () => {
    let token1Rate = BigNumber.from(0);
    const token2Rate = BigNumber.from(10).pow(3);

    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      const x = BigNumber.from(10).pow(1);
      token1Rate = token1Rate.add(x);
      rates.push(x);
    }
    await setupTestEnv(rates, token2Rate);

    for (let i = 0; i < numSources; i++) {
      const r = (await fund.balancesOf(actuary.address, sources[i].address)).rate;
      expect(r).eq(rates[i]);
    }
    expect((await fund.balancerBalanceOf(actuary.address, token1.address)).rateValue).eq(token1Rate);
    expect((await fund.balancesOf(actuary.address, token2Source.address)).rate).eq(token2Rate);

    // Because some time passed differently while adding sources, we must get to a "zero" state
    await fund.syncAsset(actuary.address, 0, token1.address);
    let curTime1 = await currentTime();
    await fund.syncAsset(actuary.address, 0, token2.address);
    let curTime2 = await currentTime();

    const totalRate = token1Rate.add(token2Rate);
    const totalsBefore = await fund.balancerTotals(actuary.address);
    let fundToken1Balance = await token1.balanceOf(fund.address);
    let fundToken2Balance = await token2.balanceOf(fund.address);
    const sourcesToken1Balances = await sourceTokenBalances(token1);
    expect(totalsBefore.rate).eq(totalRate);

    console.log('ADVANCE 10');
    await advanceTimeAndBlock(10);
    await fund.syncAsset(actuary.address, 0, token1.address);
    const timed1 = await timeDiff(curTime1);
    curTime1 = await currentTime();

    await fund.syncAsset(actuary.address, 0, token2.address);
    const timed2 = await timeDiff(curTime2);
    curTime2 = await currentTime();

    for (let i = 0; i < numSources; i++) {
      const t = await token1.balanceOf(sources[i].address);
      expect(t).eq(sourcesToken1Balances[i].sub(rates[i].mul(timed1)));
      sourcesToken1Balances[i] = t;
    }

    fundToken1Balance = fundToken1Balance.add(token1Rate.mul(timed1));
    fundToken2Balance = fundToken2Balance.add(token2Rate.mul(timed2).mul(2));
    expect(await token1.balanceOf(fund.address)).eq(fundToken1Balance);
    expect(await token2.balanceOf(fund.address)).eq(fundToken2Balance);

    // Must add 1 for the token rate because 1 second of token1 rate occurs from
    // syncing token2
    expect((await fund.balancerTotals(actuary.address)).accum).eq(
      fundToken1Balance.add(fundToken2Balance.div(2)).add(token1Rate)
    );

    /*
    console.log(timed1);
    console.log(timed2);
    console.log('token1', await fund.balancerBalanceOf(actuary.address, token1.address));
    console.log('token2', await fund.balancerBalanceOf(actuary.address, token2.address));
    console.log('balances token2', await fund.balancesOf(actuary.address, token2Source.address));
    console.log(await token2.balanceOf(fund.address));
    console.log('Total ', await fund.balancerTotals(actuary.address));
    */
  });

  // This test does NOT test the correct balancing logic
  // It ensures the correct amount of tokens are received and premium burnt
  it('Test swap', async () => {
    let token1Rate = BigNumber.from(0);
    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      const x = BigNumber.from(100);
      token1Rate = token1Rate.add(x);
      rates.push(x);
    }
    await setupTestEnv(rates, BigNumber.from(100));

    await advanceTimeAndBlock(100);
    await fund.syncAsset(actuary.address, 0, token1.address);
    await fund.syncAsset(actuary.address, 0, token2.address);

    // token1 swap
    let amt1 = BigNumber.from(1000);
    let minAmt1 = amt1.mul(95).div(100);
    await fund.swapAsset(actuary.address, user.address, user.address, amt1, token1.address, minAmt1);
    let burnt = await actuary.premiumBurnt(user.address);
    const token1bal = await token1.balanceOf(user.address);
    expect(token1bal).gte(minAmt1);
    expect(burnt).eq(amt1);

    // token2 swap
    let amt2 = BigNumber.from(100);
    let minAmt2 = amt2.mul(2).mul(95).div(100);
    await fund.swapAsset(actuary.address, user.address, user.address, amt2, token2.address, minAmt2);
    const token2bal = await token2.balanceOf(user.address);
    expect(token2bal).gte(minAmt2);
    expect((await actuary.premiumBurnt(user.address)).sub(burnt)).eq(amt2);
    burnt = await actuary.premiumBurnt(user.address);

    // Multiple token swap
    await advanceTimeAndBlock(20);
    await fund.syncAsset(actuary.address, 0, token1.address);
    await fund.syncAsset(actuary.address, 0, token2.address);
    amt1 = BigNumber.from(1500);
    amt2 = BigNumber.from(200);
    minAmt1 = amt1.mul(95).div(100);
    minAmt2 = amt2.mul(2).mul(95).div(100);
    const swapInstructions: PremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: amt1,
      targetToken: token1.address,
      minAmount: minAmt1,
      recipient: user.address,
    });
    swapInstructions.push({
      valueToSwap: amt2,
      targetToken: token2.address,
      minAmount: minAmt2,
      recipient: user.address,
    });
    // TODO: Test return values
    // let res = await fund.callStatic.swapAssets(actuary.address, user.address, user.address, swapInstructions);
    // console.log(res);
    await fund.swapAssets(actuary.address, user.address, user.address, swapInstructions);
    expect(await token1.balanceOf(user.address)).gte(token1bal.add(minAmt1));
    expect(await token2.balanceOf(user.address)).gte(token2bal.add(minAmt2));
    expect((await actuary.premiumBurnt(user.address)).sub(burnt)).eq(amt1.add(amt2));
  });
});
