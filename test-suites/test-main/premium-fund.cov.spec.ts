import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';

import { WAD, ZERO_ADDRESS } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { currentTime, advanceBlock } from '../../helpers/runtime-utils';
import { MockPremiumActuary, MockPremiumSource, MockPremiumFund, MockERC20, IPremiumFund } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Premium Fund', (testEnv: TestEnv) => {
  let fund: MockPremiumFund;
  let actuary: MockPremiumActuary;
  const sources: MockPremiumSource[] = []; // todo: mapping of tokens => sources
  let token2Source: MockPremiumSource;
  let cc: MockERC20;
  let token1: MockERC20;
  let token2: MockERC20;
  let user: SignerWithAddress;

  let numSources = 0;

  const createPremiumSource = async (premiumToken: string) => {
    const source = await Factories.MockPremiumSource.deploy(premiumToken, cc.address);
    sources.push(source);
  };

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockERC20.deploy('Collateral', '$CC', 18);
    fund = await Factories.MockPremiumFund.deploy(cc.address);
    actuary = await Factories.MockPremiumActuary.deploy(fund.address, cc.address);

    token1 = await Factories.MockERC20.deploy('Mock token1', 'MCK', 18);
    token2 = await Factories.MockERC20.deploy('Mock token2', 'MCK2', 18);
    numSources = 5;

    for (let i = 0; i < numSources; i++) {
      await createPremiumSource(token1.address);
      await token1.mint(sources[i].address, WAD.mul((i + 1) * 100));
    }

    token2Source = await Factories.MockPremiumSource.deploy(token2.address, cc.address);
    await token2.mint(token2Source.address, WAD.mul(100));

    await fund.connect(user).setApprovalsFor(testEnv.deployer.address, 1, true);
  });

  const setupTestEnv = async (rates: BigNumber[], token2rate: BigNumber) => {
    await fund.registerPremiumActuary(actuary.address, true);
    await fund.setPrice(token1.address, WAD);
    await fund.setPrice(token2.address, WAD.div(2));

    if (rates.length !== numSources) {
      throw Error('Incorrect rates length');
    }

    for (let i = 0; i < numSources; i++) {
      await actuary.addSource(sources[i].address);
      await actuary.setRate(sources[i].address, rates[i], testEnv.covGas());
    }

    await actuary.addSource(token2Source.address);
    await actuary.setRate(token2Source.address, token2rate, testEnv.covGas());
  };

  const sourceTokenBalances = async (token: MockERC20) => {
    const balances: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      balances.push(await token.balanceOf(sources[i].address));
    }

    return balances;
  };

  const timeDiff = async (earlier: number) => (await currentTime()) - earlier;

  const registerActuaryAndSource = async (rate = 10) => {
    await fund.registerPremiumActuary(actuary.address, true);

    await actuary.addSource(sources[0].address);
    await fund.setPrice(token1.address, WAD);
    await actuary.setRate(sources[0].address, rate);
  };

  it('Must add actuary before adding source', async () => {
    // Must add actuary before adding source
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;
    await fund.registerPremiumActuary(actuary.address, true);
    await actuary.addSource(sources[0].address);
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;
  });

  /*
  it('Must set rate before syncing', async() => {
    await registerActuaryAndSource();

    // Must set rate before syncing
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await actuary.setRate(sources[0].address, 10);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
  });
  */

  it('Cant sync while token is paused GLOBALLY', async () => {
    await registerActuaryAndSource();

    await fund.setPaused(ZERO_ADDRESS, token1.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await fund.setPaused(ZERO_ADDRESS, token1.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
  });

  it('Can update/finish while token is paused GLOBALLY', async () => {
    await registerActuaryAndSource();
    const rate = 100;

    await fund.setPaused(ZERO_ADDRESS, token1.address, true);
    await actuary.setRate(sources[0].address, rate, testEnv.covGas());
    expect((await fund.balancesOf(actuary.address, sources[0].address, testEnv.covGas())).rate).eq(100);

    const bal = await token1.balanceOf(fund.address);
    await advanceBlock((await currentTime()) + 10);
    await actuary.callPremiumAllocationFinished(sources[0].address, rate * 20, testEnv.covGas());
    expect(await token1.balanceOf(fund.address)).gt(bal);
  });

  it('Cant sync/swap while token is paused IN BALANCER', async () => {
    await registerActuaryAndSource();

    await fund.setPaused(actuary.address, token1.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await expect(fund.swapAsset(actuary.address, user.address, user.address, 10, token1.address, 9)).to.be.reverted;
    await fund.setPaused(actuary.address, token1.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
  });

  it('Cant sync/swap while actuary is paused', async () => {
    await registerActuaryAndSource();

    await fund.setPaused(actuary.address, ZERO_ADDRESS, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await expect(fund.swapAsset(actuary.address, user.address, user.address, 10, token1.address, 9, testEnv.covGas()))
      .to.be.reverted;
    await fund.setPaused(actuary.address, ZERO_ADDRESS, false);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
    await actuary.removeSource(sources[0].address);
  });

  it('Premium allocation finished', async () => {
    const rate = 10;
    await registerActuaryAndSource(rate);

    await advanceBlock((await currentTime()) + 10);
    await fund.syncAsset(actuary.address, 0, token1.address);
    expect((await fund.balancesOf(actuary.address, sources[0].address, testEnv.covGas())).rate).eq(10);
    await actuary.callPremiumAllocationFinished(sources[0].address, rate * 20, testEnv.covGas());
    expect((await fund.balancesOf(actuary.address, sources[0].address, testEnv.covGas())).rate).eq(0);
    await fund.registerPremiumActuary(actuary.address, false, testEnv.covGas());
  });

  it('Premium allocation finished before sync', async () => {
    const rate = 10;
    await registerActuaryAndSource(rate);

    await advanceBlock((await currentTime()) + 10);
    await actuary.callPremiumAllocationFinished(sources[0].address, rate * 20, testEnv.covGas());
  });

  it('Rates', async () => {
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
      const r = (await fund.balancesOf(actuary.address, sources[i].address, testEnv.covGas())).rate;
      expect(r).eq(rates[i]);
    }
    expect((await fund.balancerBalanceOf(actuary.address, token1.address, testEnv.covGas())).rateValue).eq(token1Rate);
    expect((await fund.balancesOf(actuary.address, token2Source.address, testEnv.covGas())).rate).eq(token2Rate);

    // Because some time passed differently while adding sources, we must get to a "zero" state
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
    let curTime1 = await currentTime();
    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas());
    let curTime2 = await currentTime();

    const totalRate = token1Rate.add(token2Rate);
    const totalsBefore = await fund.balancerTotals(actuary.address);
    let fundToken1Balance = await token1.balanceOf(fund.address);
    let fundToken2Balance = await token2.balanceOf(fund.address);
    const sourcesToken1Balances = await sourceTokenBalances(token1);
    expect(totalsBefore.rate).eq(totalRate);

    await advanceBlock((await currentTime()) + 10);

    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
    let timed1 = await timeDiff(curTime1);
    curTime1 = await currentTime();

    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas());
    let timed2 = await timeDiff(curTime2);
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
    expect((await fund.balancerTotals(actuary.address)).accum).eq(
      fundToken1Balance.add(fundToken2Balance.div(2)).add(token1Rate.mul((await currentTime()) - curTime1))
    );

    // syncAssets
    await advanceBlock((await currentTime()) + 10);
    await fund.syncAssets(actuary.address, 0, [token1.address, token2.address], testEnv.covGas());
    timed1 = await timeDiff(curTime1);
    timed2 = await timeDiff(curTime2);

    fundToken1Balance = fundToken1Balance.add(token1Rate.mul(timed1));
    fundToken2Balance = fundToken2Balance.add(token2Rate.mul(timed2).mul(2));
    expect(await token1.balanceOf(fund.address)).eq(fundToken1Balance);
    expect(await token2.balanceOf(fund.address)).eq(fundToken2Balance);
  });

  // This test does NOT test the correct balancing logic
  // It ensures the correct amount of tokens are received and premium burnt
  it('Swap', async () => {
    let token1Rate = BigNumber.from(0);
    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      const x = BigNumber.from(100);
      token1Rate = token1Rate.add(x);
      rates.push(x);
    }
    await setupTestEnv(rates, BigNumber.from(100));

    await advanceBlock((await currentTime()) + 100);

    await cc.mint(actuary.address, 10000);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas());

    // token1 swap
    let amt1 = BigNumber.from(1000);
    let minAmt1 = amt1.mul(95).div(100);
    await fund.swapAsset(actuary.address, user.address, user.address, amt1, token1.address, minAmt1, testEnv.covGas());

    let burnt = await actuary.premiumBurnt(user.address);
    const token1bal = await token1.balanceOf(user.address);
    expect(token1bal).gte(minAmt1);
    expect(burnt).eq(amt1);

    // token2 swap
    let amt2 = BigNumber.from(100);
    let minAmt2 = amt2.mul(2).mul(95).div(100);
    await fund.swapAsset(actuary.address, user.address, user.address, amt2, token2.address, minAmt2, testEnv.covGas());
    const token2bal = await token2.balanceOf(user.address);
    expect(token2bal).gte(minAmt2);
    expect((await actuary.premiumBurnt(user.address)).sub(burnt)).eq(amt2);
    burnt = await actuary.premiumBurnt(user.address);

    // Multiple token swap
    await advanceBlock((await currentTime()) + 40);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas());
    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas());
    amt1 = BigNumber.from(1500);
    amt2 = BigNumber.from(200);
    minAmt1 = amt1.mul(95).div(100);
    minAmt2 = amt2.mul(2).mul(95).div(100);
    const swapInstructions: IPremiumFund.SwapInstructionStruct[] = [];
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

    const res = await fund.callStatic.swapAssets(actuary.address, user.address, swapInstructions);
    expect(res[0]).gte(minAmt1);
    expect(res[1]).gte(minAmt2);
    await fund.swapAssets(actuary.address, user.address, swapInstructions, testEnv.covGas());
    {
      const userBal = await token1.balanceOf(user.address);
      expect(userBal).gte(token1bal.add(res[0]));
      // expect(userBal).lte(token1bal.add(amt1));
    }
    {
      const userBal = await token2.balanceOf(user.address);
      expect(userBal).gte(token2bal.add(res[1]));
      if (!testEnv.underCoverage) {
        expect(userBal).lte(token2bal.add(amt2.mul(2)));
      }
    }
    expect((await actuary.premiumBurnt(user.address)).sub(burnt)).eq(amt1.add(amt2));
  });

  it('Swap without sync', async () => {
    await fund.registerPremiumActuary(actuary.address, true);
    await cc.mint(actuary.address, 10000);
    await actuary.addSource(sources[0].address);

    await fund.setPrice(token1.address, WAD);
    await actuary.setRate(sources[0].address, 2000);
    // Auto replenish doesn't need to be set because  balance.accumAmount < c.sA in _swapAsset

    await advanceBlock((await currentTime()) + 20);
    const amt1 = BigNumber.from(1000);
    const minAmt1 = amt1.mul(95).div(100);
    const token1bal = await token1.balanceOf(user.address);
    await fund.swapAsset(actuary.address, user.address, user.address, amt1, token1.address, minAmt1, testEnv.covGas());
    {
      const userBal = await token1.balanceOf(user.address);
      expect(userBal).gte(token1bal.add(minAmt1));
      expect(userBal).lte(token1bal.add(amt1));
    }
  });

  it('Swap auto replenish', async () => {
    await fund.registerPremiumActuary(actuary.address, true);
    await cc.mint(actuary.address, 10000);
    await actuary.addSource(sources[0].address);

    await fund.setPrice(token1.address, WAD);
    await actuary.setRate(sources[0].address, 2000, testEnv.covGas());
    await fund.setAutoReplenish(actuary.address, token1.address);

    await advanceBlock((await currentTime()) + 20);

    const amt1 = BigNumber.from(1500);
    const minAmt1 = amt1.mul(95).div(100);
    const token1bal = await token1.balanceOf(user.address);
    const swapInstructions: IPremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: amt1,
      targetToken: token1.address,
      minAmount: minAmt1,
      recipient: user.address,
    });

    await fund.swapAssets(actuary.address, user.address, swapInstructions, testEnv.covGas());
    {
      const userBal = await token1.balanceOf(user.address);
      expect(userBal).gte(token1bal.add(minAmt1));
      expect(userBal).lte(token1bal.add(amt1));
    }
  });

  it('Swap auto replenish (2)', async () => {
    await fund.registerPremiumActuary(actuary.address, true);
    await cc.mint(actuary.address, 10000);
    await actuary.addSource(sources[0].address);
    await actuary.addSource(sources[1].address);

    await fund.setPrice(token1.address, WAD);
    await actuary.setRate(sources[0].address, 1000);
    await actuary.setRate(sources[1].address, 1000);
    await fund.setAutoReplenish(actuary.address, token1.address);

    await advanceBlock((await currentTime()) + 20);

    const amt1 = BigNumber.from(1500);
    const minAmt1 = amt1.mul(95).div(100);
    const token1bal = await token1.balanceOf(user.address);
    const swapInstructions: IPremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: amt1,
      targetToken: token1.address,
      minAmount: minAmt1,
      recipient: user.address,
    });

    await fund.swapAssets(actuary.address, user.address, swapInstructions, testEnv.covGas());
    {
      const userBal = await token1.balanceOf(user.address);
      expect(userBal).gte(token1bal.add(minAmt1));
      expect(userBal).lte(token1bal.add(amt1));
    }
  });

  it('Drawdown flat', async () => {
    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      const x = BigNumber.from(1000);
      rates.push(x);
    }
    const drawdownAmt = 1000;
    await setupTestEnv(rates, BigNumber.from(100));
    await cc.mint(actuary.address, 10000);
    await actuary.setDrawdown(drawdownAmt);

    const flatPct = 1_00_00; // 100%
    await fund.setAssetConfig(actuary.address, cc.address, {
      spConst: 0,
      calc: BigNumber.from(flatPct)
        .shl(144 + 64)
        .or(BigNumber.from(1).shl(14 + 32 + 64 + 144)), // calc.n = 100%; calc.flags = BF_EXTERNAL
    });

    await advanceBlock((await currentTime()) + 10);
    await fund.syncAsset(actuary.address, 0, cc.address, testEnv.covGas());

    // NB! CC is an exeption - it is not transferred on sync, but stays on actuary's balance
    // this simplifies claim logic for an Index Pool
    expect(await cc.balanceOf(fund.address)).eq(0);
    expect(await cc.balanceOf(actuary.address)).eq(10000);

    let swapAmt = 200;
    await fund.swapAsset(actuary.address, user.address, user.address, swapAmt, cc.address, swapAmt, testEnv.covGas());
    const bal = await cc.balanceOf(user.address);
    expect(bal).eq(swapAmt);
    expect(await cc.balanceOf(fund.address)).eq(0);
    expect(bal.add(await cc.balanceOf(actuary.address))).eq(10000);

    swapAmt = 400;
    const swapInstructions: IPremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: swapAmt,
      targetToken: cc.address,
      minAmount: 0,
      recipient: user.address,
    });

    // 2nd drawdown instruction will be ignored
    swapInstructions.push({
      valueToSwap: swapAmt,
      targetToken: cc.address,
      minAmount: 0,
      recipient: user.address,
    });

    await fund.swapAssets(actuary.address, user.address, swapInstructions, testEnv.covGas());

    expect(await cc.balanceOf(user.address)).eq(bal.add(swapAmt));
    expect(await fund.availableFee(cc.address)).eq(0);
  });

  it('Drawdown curve', async () => {
    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      const x = BigNumber.from(1000);
      rates.push(x);
    }
    const drawdownAmt = 1000;
    await setupTestEnv(rates, BigNumber.from(100));
    await cc.mint(actuary.address, 10000);
    await actuary.setDrawdown(drawdownAmt);
    const userDrawdownAmt = 1000 / 10;
    await actuary.setUserShare(userDrawdownAmt);

    const flatPct = 20_00; // 20%
    await fund.setAssetConfig(actuary.address, cc.address, {
      spConst: 0,
      calc: BigNumber.from(flatPct)
        .shl(144 + 64)
        .or(BigNumber.from(1).shl(14 + 32 + 64 + 144)), // calc.n = 20%; calc.flags = BF_EXTERNAL
    });

    await advanceBlock((await currentTime()) + 10);
    await fund.syncAsset(actuary.address, 0, cc.address, testEnv.covGas());

    // NB! CC is an exeption - it is not transferred on sync, but stays on actuary's balance
    // this simplifies claim logic for an Index Pool
    expect(await cc.balanceOf(fund.address)).eq(0);
    expect(await cc.balanceOf(actuary.address)).eq(10000);

    const flatAmt = (userDrawdownAmt * flatPct) / 1_00_00;
    {
      // flat portion
      const amount = await fund.callStatic.swapAsset(
        actuary.address,
        user.address,
        user.address,
        flatAmt,
        cc.address,
        0,
        testEnv.covGas()
      );
      expect(amount).eq(flatAmt);
    }

    // flat + curve
    const swapAmt = 4 * flatAmt;
    await fund.swapAsset(actuary.address, user.address, user.address, swapAmt, cc.address, 0, testEnv.covGas());

    const bal = await cc.balanceOf(user.address);
    expect(bal).gt(flatAmt);
    expect(bal).lt(swapAmt);
    const fee = await fund.availableFee(cc.address);
    expect(fee).gt(0);
    expect(await cc.balanceOf(fund.address)).eq(fee);
    expect(bal.add(await cc.balanceOf(actuary.address)).add(fee)).eq(10000);
  });

  it('Swap above balance to collect fee', async () => {
    await fund.registerPremiumActuary(actuary.address, true);
    await cc.mint(actuary.address, 100000);
    await actuary.addSource(sources[0].address);
    await actuary.setRate(sources[0].address, 1000);
    await fund.setPrice(token1.address, WAD);

    // await fund.setAutoReplenish(actuary.address, token1.address);
    await advanceBlock((await currentTime()) + 3);
    await fund.syncAsset(actuary.address, 0, token1.address);

    const amt1 = BigNumber.from(8000);
    await fund.swapAsset(actuary.address, user.address, user.address, amt1, token1.address, 0, testEnv.covGas());

    const fee = await fund.availableFee(token1.address);
    const diff = amt1.sub(await token1.balanceOf(user.address));
    expect(fee).gt(0);
    expect(fee).eq(diff);

    await advanceBlock((await currentTime()) + 20);
    await fund.syncAsset(actuary.address, 0, token1.address);

    {
      const swapInstructions: IPremiumFund.SwapInstructionStruct[] = [];
      swapInstructions.push({
        valueToSwap: amt1,
        targetToken: cc.address,
        minAmount: 0,
        recipient: user.address,
      });

      await fund.swapAssets(actuary.address, user.address, swapInstructions, testEnv.covGas());
    }
    const fee1 = await fund.availableFee(token1.address);
    expect(fee1).eq(fee.add(amt1.sub(await token1.balanceOf(user.address)).sub(diff)));

    const user2 = testEnv.users[1];

    {
      const results = await fund.callStatic.collectFees([token1.address, cc.address], WAD, user2.address);
      expect(results[0]).eq(0);
      expect(results[1]).eq(0);
    }
    {
      const results = await fund.callStatic.collectFees([token1.address, cc.address], 0, user2.address);
      expect(results[0]).eq(fee1);
      expect(results[1]).eq(0);
    }
    {
      expect(await token1.balanceOf(user2.address)).eq(0);

      await fund.collectFees([token1.address, cc.address], 0, user2.address);
      expect(await fund.availableFee(token1.address)).eq(0);
      expect(await fund.availableFee(cc.address)).eq(0);

      expect(await token1.balanceOf(user2.address)).eq(fee1);
      expect(await cc.balanceOf(user2.address)).eq(0);
    }
  });
});
