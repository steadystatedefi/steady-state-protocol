import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';

// import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { advanceTimeAndBlock } from '../../helpers/runtime-utils';
import { CollateralCurrency, MockPremiumActuary, MockPremiumSource, MockPremiumFund, MockERC20 } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Premium Fund', (testEnv: TestEnv) => {
  let fund: MockPremiumFund;
  let actuary: MockPremiumActuary;
  const sources: MockPremiumSource[] = []; // todo: mapping of tokens => sources
  let cc: CollateralCurrency;
  let token: MockERC20;
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

    token = await Factories.MockERC20.deploy('Mock Token', 'MCK', 18);
    numSources = 5;

    for (let i = 0; i < numSources; i++) {
      await createPremiumSource(token.address);
      await token.mint(
        sources[i].address,
        BigNumber.from(10)
          .pow(18)
          .mul((i + 1) * 100)
      );
    }
  });

  const setupTestEnv = async (rates: BigNumber[]) => {
    await fund.registerPremiumActuary(actuary.address, true);
    await fund.setDefaultConfig(
      actuary.address,
      0,
      // BigNumber.from(10).pow(18),
      0,
      0,
      StarvationPointMode.Constant,
      20
    );

    if (rates.length !== numSources) {
      throw Error('Incorrect rates length');
    }

    // await actuary.addSource(sources[0].address);
    for (let i = 0; i < numSources; i++) {
      await actuary.addSource(sources[i].address);
      await actuary.setRate(sources[i].address, rates[i]);
    }

    fund.setPrice(token.address, BigNumber.from(10).pow(18));
  };

  // When increment is set for premiumAllocationUpdated
  // it is a certain amount asked by the actuary
  const requestPremiumAmount = async (index: number, increment: BigNumber) => {
    await actuary.callPremiumAllocationUpdated(sources[index].address, 0, increment, 0);
  };

  /*
  it('Register actuary and premium sources', async () => {
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;
    await fund.registerPremiumActuary(actuary.address, true);
    await actuary.addSource(sources[0].address);
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;
  });
  */

  it('Test rates', async () => {
    // await expect(actuary.addSource(sources[0].address)).to.be.reverted;
    const rates: BigNumber[] = [];
    for (let i = 0; i < numSources; i++) {
      rates.push(BigNumber.from(10).pow(8));
    }
    await setupTestEnv(rates);
    // await fund.registerPremiumActuary(actuary.address, true);

    console.log(await fund.getConifg(actuary.address, token.address));

    console.log(await token.balanceOf(sources[0].address));
    console.log(await token.balanceOf(fund.address));

    console.log(await fund.balancesOf(actuary.address, sources[0].address));

    await advanceTimeAndBlock(10);
    await fund.syncAsset(actuary.address, 0, token.address);
    console.log(await token.balanceOf(sources[0].address));
    console.log(await token.balanceOf(fund.address));

    await advanceTimeAndBlock(1000);
    await fund.syncAsset(actuary.address, 0, token.address);
    console.log(await token.balanceOf(sources[0].address));
    console.log(await token.balanceOf(fund.address));
  });
});
