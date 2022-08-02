import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { MAX_UINT, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress } from '../../helpers/runtime-utils';
import { MockCollateralFund, MockCollateralCurrency, MockYieldDistributor, MockInsurerForYield } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Yield distributor', (testEnv: TestEnv) => {
  let cc: MockCollateralCurrency;
  let token0: MockCollateralCurrency;
  let fund: MockCollateralFund;
  let insurer: MockInsurerForYield;
  let dist: MockYieldDistributor;
  let user0: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  before(async () => {
    user0 = testEnv.deployer;
    [user1, user2, user3] = testEnv.users;
    cc = await Factories.MockCollateralCurrency.deploy('Collateral Currency', '$CC', 18);
    dist = await Factories.MockYieldDistributor.deploy(cc.address);
    cc.setBorrowManager(dist.address);

    token0 = await Factories.MockCollateralCurrency.deploy('Collateral Asset', '$TK0', 18);
    fund = await Factories.MockCollateralFund.deploy(cc.address);
    await cc.registerLiquidityProvider(fund.address);

    await token0.registerLiquidityProvider(user0.address);
    await fund.addAsset(token0.address, zeroAddress());
    await fund.setPriceOf(token0.address, WAD);

    // await token0.mint(user1.address, WAD);
    // await token0.mint(user2.address, WAD);

    insurer = await Factories.MockInsurerForYield.deploy(cc.address);
    await cc.registerInsurer(insurer.address);

    await insurer.mint(user1.address, WAD);
    await insurer.mint(user2.address, WAD);
    await insurer.connect(user1).approve(dist.address, WAD);
    await insurer.connect(user2).approve(dist.address, WAD);
  });

  enum YieldSourceType {
    None,
    Passive,
  }

  it('Stake', async () => {
    await token0.connect(user1).approve(fund.address, WAD);

    await dist.addYieldSource(user3.address, YieldSourceType.Passive);
    await dist.connect(user1).stake(insurer.address, WAD, user1.address);
  });
});
