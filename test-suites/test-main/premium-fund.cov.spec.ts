import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';

import { WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { currentTime, advanceBlock } from '../../helpers/runtime-utils';
import { MockPremiumActuary, MockPremiumSource, MockPremiumFund, MockERC20, PremiumFund } from '../../types';

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

  enum StarvationPointMode {
    RateFactor = 0 + 64, // + BF_AUTO_REPLENISH
    GlobalRateFactor = 1 + 64, // + BF_AUTO_REPLENISH
    Constant = 2,
    GlobalConstant = 3,
  }

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
      await token1.mint(
        sources[i].address,
        BigNumber.from(10)
          .pow(18)
          .mul((i + 1) * 100)
      );
    }

    token2Source = await Factories.MockPremiumSource.deploy(token2.address, cc.address);
    await token2.mint(token2Source.address, WAD.mul(100));

    await fund.setDefaultConfig(
      actuary.address,
      0,
      // WAD,
      0,
      0,
      StarvationPointMode.Constant,
      20
    );
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
      await actuary.setRate(sources[i].address, rates[i], testEnv.covGas(30000000));
    }

    await actuary.addSource(token2Source.address);
    await actuary.setRate(token2Source.address, token2rate, testEnv.covGas(30000000));
  };

  const sourceTokenBalances = async (token: MockERC20) => {
    const balances: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      balances.push(await token.balanceOf(sources[i].address));
    }

    return balances;
  };

  const timeDiff = async (earlier: number) => (await currentTime()) - earlier;

  const registerActuaryAndSource = async () => {
    await fund.registerPremiumActuary(actuary.address, true);
    await actuary.addSource(sources[0].address);
    await fund.setPrice(token1.address, WAD);
    await actuary.setRate(sources[0].address, 10);
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
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
  });
  */

  it('Cant sync while token is paused GLOBALLY', async () => {
    await registerActuaryAndSource();

    await fund.setPausedToken(token1.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await fund.setPausedToken(token1.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
  });

  it('Cant sync/swap while token is paused IN BALANCER', async () => {
    await registerActuaryAndSource();

    await fund['setPaused(address,address,bool)'](actuary.address, token1.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await expect(fund.swapAsset(actuary.address, user.address, user.address, 10, token1.address, 9)).to.be.reverted;
    await fund['setPaused(address,address,bool)'](actuary.address, token1.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
  });

  it('Cant sync/swap while actuary is paused', async () => {
    await registerActuaryAndSource();

    await fund['setPaused(address,bool)'](actuary.address, true);
    await expect(fund.syncAsset(actuary.address, 0, token1.address)).to.be.reverted;
    await expect(
      fund.swapAsset(actuary.address, user.address, user.address, 10, token1.address, 9, testEnv.covGas(30000000))
    ).to.be.reverted;
    await fund['setPaused(address,bool)'](actuary.address, false);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
    await actuary.removeSource(sources[0].address);
  });

  it('Premium allocation finished', async () => {
    await registerActuaryAndSource();

    await advanceBlock((await currentTime()) + 10);
    await fund.syncAsset(actuary.address, 0, token1.address);
    expect((await fund.balancesOf(actuary.address, sources[0].address, testEnv.covGas(30000000))).rate).eq(10);
    await actuary.callPremiumAllocationFinished(sources[0].address, 0, testEnv.covGas(30000000));
    expect((await fund.balancesOf(actuary.address, sources[0].address, testEnv.covGas(30000000))).rate).eq(0);
    await fund.registerPremiumActuary(actuary.address, false, testEnv.covGas(30000000));
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
      const r = (await fund.balancesOf(actuary.address, sources[i].address, testEnv.covGas(30000000))).rate;
      expect(r).eq(rates[i]);
    }
    expect((await fund.balancerBalanceOf(actuary.address, token1.address, testEnv.covGas(30000000))).rateValue).eq(
      token1Rate
    );
    expect((await fund.balancesOf(actuary.address, token2Source.address, testEnv.covGas(30000000))).rate).eq(
      token2Rate
    );

    // Because some time passed differently while adding sources, we must get to a "zero" state
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
    let curTime1 = await currentTime();
    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas(30000000));
    let curTime2 = await currentTime();

    const totalRate = token1Rate.add(token2Rate);
    const totalsBefore = await fund.balancerTotals(actuary.address);
    let fundToken1Balance = await token1.balanceOf(fund.address);
    let fundToken2Balance = await token2.balanceOf(fund.address);
    const sourcesToken1Balances = await sourceTokenBalances(token1);
    expect(totalsBefore.rate).eq(totalRate);

    await advanceBlock((await currentTime()) + 10);

    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
    let timed1 = await timeDiff(curTime1);
    curTime1 = await currentTime();

    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas(30000000));
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

    // Must add 1 for the token rate because 1 second of token1 rate occurs from
    // syncing token2
    if (!testEnv.underCoverage) {
      expect((await fund.balancerTotals(actuary.address)).accum).eq(
        fundToken1Balance.add(fundToken2Balance.div(2)).add(token1Rate)
      );
    }

    // syncAssets
    await advanceBlock((await currentTime()) + 10);
    await fund.syncAssets(actuary.address, 0, [token1.address, token2.address]);
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
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas(30000000));

    // token1 swap
    let amt1 = BigNumber.from(1000);
    let minAmt1 = amt1.mul(95).div(100);
    await fund.swapAsset(
      actuary.address,
      user.address,
      user.address,
      amt1,
      token1.address,
      minAmt1,
      testEnv.covGas(30000000)
    );

    let burnt = await actuary.premiumBurnt(user.address);
    const token1bal = await token1.balanceOf(user.address);
    expect(token1bal).gte(minAmt1);
    expect(burnt).eq(amt1);

    // token2 swap
    let amt2 = BigNumber.from(100);
    let minAmt2 = amt2.mul(2).mul(95).div(100);
    await fund.swapAsset(
      actuary.address,
      user.address,
      user.address,
      amt2,
      token2.address,
      minAmt2,
      testEnv.covGas(30000000)
    );
    const token2bal = await token2.balanceOf(user.address);
    expect(token2bal).gte(minAmt2);
    expect((await actuary.premiumBurnt(user.address)).sub(burnt)).eq(amt2);
    burnt = await actuary.premiumBurnt(user.address);

    // Multiple token swap
    await advanceBlock((await currentTime()) + 40);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));
    await fund.syncAsset(actuary.address, 0, token2.address, testEnv.covGas(30000000));
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

    const res = await fund.callStatic.swapAssets(actuary.address, user.address, user.address, swapInstructions);
    expect(res[0]).gte(minAmt1);
    expect(res[1]).gte(minAmt2);
    await fund.swapAssets(actuary.address, user.address, user.address, swapInstructions, testEnv.covGas(30000000));
    {
      const userBal = await token1.balanceOf(user.address);
      expect(userBal).gte(token1bal.add(res[0]));
      // expect(userBal).lte(token1bal.add(amt1));
    }
    {
      const userBal = await token2.balanceOf(user.address);
      expect(userBal).gte(token2bal.add(res[1]));
      expect(userBal).lte(token2bal.add(amt2.mul(2)));
    }
    expect((await actuary.premiumBurnt(user.address)).sub(burnt)).eq(amt1.add(amt2));
  });

  it('Swap auto replenish', async () => {
    await fund.registerPremiumActuary(actuary.address, true);
    await cc.mint(actuary.address, 10000);
    await actuary.addSource(sources[0].address);

    await fund.setPrice(token1.address, WAD);
    await actuary.setRate(sources[0].address, 2000);
    await fund.setAutoReplenish(actuary.address, token1.address);
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));

    await advanceBlock((await currentTime()) + 20);

    const amt1 = BigNumber.from(1500);
    const minAmt1 = amt1.mul(95).div(100);
    const token1bal = await token1.balanceOf(user.address);
    const swapInstructions: PremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: amt1,
      targetToken: token1.address,
      minAmount: minAmt1,
      recipient: user.address,
    });

    await fund.swapAssets(actuary.address, user.address, user.address, swapInstructions, testEnv.covGas(30000000));
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
    await fund.syncAsset(actuary.address, 0, token1.address, testEnv.covGas(30000000));

    await advanceBlock((await currentTime()) + 20);

    const amt1 = BigNumber.from(1500);
    const minAmt1 = amt1.mul(95).div(100);
    const token1bal = await token1.balanceOf(user.address);
    const swapInstructions: PremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: amt1,
      targetToken: token1.address,
      minAmount: minAmt1,
      recipient: user.address,
    });

    await fund.swapAssets(actuary.address, user.address, user.address, swapInstructions, testEnv.covGas(30000000));
    {
      const userBal = await token1.balanceOf(user.address);
      expect(userBal).gte(token1bal.add(minAmt1));
      expect(userBal).lte(token1bal.add(amt1));
    }
  });

  it('Collateral currency', async () => {
    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      const x = BigNumber.from(1000);
      rates.push(x);
    }
    const drawdownAmt = 1000;
    await setupTestEnv(rates, BigNumber.from(100));
    await cc.mint(actuary.address, 10000);
    await actuary.setDrawdown(drawdownAmt);

    await advanceBlock((await currentTime()) + 10);
    await fund.syncAsset(actuary.address, 0, cc.address, testEnv.covGas(30000000));
    expect(await cc.balanceOf(fund.address)).eq(drawdownAmt);

    let swapAmt = 200;
    let swapAmtMin = BigNumber.from(swapAmt).mul(95).div(100);
    await fund.swapAsset(
      actuary.address,
      user.address,
      user.address,
      swapAmt,
      cc.address,
      swapAmtMin,
      testEnv.covGas(30000000)
    );
    const bal = await cc.balanceOf(user.address);
    expect(bal).gte(swapAmtMin);

    swapAmt = 400;
    swapAmtMin = BigNumber.from(swapAmt).mul(95).div(100);
    const swapInstructions: PremiumFund.SwapInstructionStruct[] = [];
    swapInstructions.push({
      valueToSwap: swapAmt,
      targetToken: cc.address,
      minAmount: swapAmtMin,
      recipient: user.address,
    });
    swapInstructions.push({
      valueToSwap: swapAmt,
      targetToken: cc.address,
      minAmount: swapAmtMin,
      recipient: user.address,
    });

    await fund.swapAssets(actuary.address, user.address, user.address, swapInstructions, testEnv.covGas(30000000));

    {
      const userBal = await cc.balanceOf(user.address);
      expect(userBal).gte(bal.add(swapAmtMin.mul(2)));
      expect(userBal).lte(bal.add(swapAmt * 2));
    }
  });
});
