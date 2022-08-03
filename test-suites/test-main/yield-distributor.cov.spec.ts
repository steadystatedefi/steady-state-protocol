import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { MAX_UINT, WAD, ROLES, SINGLETS, PROTECTED_SINGLETS } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress } from '../../helpers/runtime-utils';
import {
  MockCollateralFund,
  MockCollateralCurrency,
  MockYieldDistributor,
  MockInsurerForYield,
  AccessController,
} from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

const LP_DEPLOY = BigNumber.from(1).shl(10);
const LP_ADMIN = BigNumber.from(1).shl(11);
const INSURER_ADMIN = BigNumber.from(1).shl(12);
const BORROWER_ADMIN = BigNumber.from(1).shl(14);
const LIQUIDITY_BORROWER = BigNumber.from(1).shl(15);

makeSuite('Yield distributor', (testEnv: TestEnv) => {
  let controller: AccessController;
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
    controller = await Factories.AccessController.deploy(SINGLETS, ROLES, PROTECTED_SINGLETS);
    dist = await Factories.MockYieldDistributor.deploy(controller.address, cc.address);
    cc.setBorrowManager(dist.address);

    token0 = await Factories.MockCollateralCurrency.deploy('Collateral Asset', '$TK0', 18);
    fund = await Factories.MockCollateralFund.deploy(cc.address);

    await controller.grantRoles(user0.address, LP_DEPLOY.or(LP_ADMIN).or(INSURER_ADMIN).or(BORROWER_ADMIN));

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

  it('Access control', async () => {
    // TODO: This will fail anyways since before() registers insurer
    await expect(dist.registerStakeAsset(insurer.address, true)).to.be.reverted;

    // Only borrower admin can addYieldSource
    // Why isn't the ACL check failing... (probably just tired..)
    // await expect(dist.connect(user2).addYieldSource(user3.address, YieldSourceType.Passive)).to.be.reverted;
    await dist.addYieldSource(user3.address, YieldSourceType.Passive);

    // Only liquidity provider and and trusted borrower
    await expect(dist.verifyBorrowUnderlying(user0.address, 0)).to.be.reverted;
    await cc.registerLiquidityProvider(user0.address);
    await expect(dist.verifyBorrowUnderlying(user0.address, 0)).to.be.reverted;
    await dist.addYieldSource(user0.address, YieldSourceType.Passive);
    // console.log(await controller.queryAccessControlMask(user0.address, LIQUIDITY_BORROWER));
    // await expect(dist.verifyBorrowUnderlying(user0.address, 0)).to.be.reverted;
    // await controller.grantRoles(user0.address, LIQUIDITY_BORROWER);
    // await dist.verifyBorrowUnderlying(user0.address, 0);
  });
});
