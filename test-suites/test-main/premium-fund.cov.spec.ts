import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';

// import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { CollateralCurrency, MockPremiumActuary, MockPremiumSource, MockPremiumFund, MockERC20 } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Premium Fund', (testEnv: TestEnv) => {
  let fund: MockPremiumFund;
  let actuary: MockPremiumActuary;
  const sources: MockPremiumSource[] = [];
  let cc: CollateralCurrency;
  let token: MockERC20;
  let user: SignerWithAddress;

  let numSources;

  const createPremiumSource = async (premiumToken: string) => {
    const source = await Factories.MockPremiumSource.deploy(premiumToken, cc.address);
    sources.push(source);
  };

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
        sources[0].address,
        BigNumber.from(10)
          .pow(18)
          .mul(i * 100)
      );
    }
  });

  it('Register actuary and premium sources', async () => {
    await expect(actuary.addSource(sources[0].address)).to.be.reverted;

    await fund.registerPremiumActuary(actuary.address, true);
    await actuary.addSource(sources[0].address);

    await actuary.callPremiumAllocationUpdated(
      sources[0].address,
      BigNumber.from(10).pow(18),
      BigNumber.from(10).pow(18),
      BigNumber.from(10).pow(8).mul(2)
    );
  });
});
