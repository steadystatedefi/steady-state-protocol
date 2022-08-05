import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish } from 'ethers';

import { MAX_UINT, RAY, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { currentTime, increaseTime } from '../../helpers/runtime-utils';
import { MockCollateralFund, MockCollateralCurrency, MockYieldDistributor, MockInsurerForYield } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite.only('Yield distributor', (testEnv: TestEnv) => {
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
    NullPull,
  }

  it('Stake and unstake', async () => {
    expect(await dist.totalStakedCollateral()).eq(0);
    expect(await insurer.balanceOf(dist.address)).eq(0);

    await insurer.connect(user1).approve(dist.address, WAD.div(2));
    await dist.connect(user1).stake(insurer.address, MAX_UINT, user1.address);
    expect(await dist.totalStakedCollateral()).eq(WAD.div(2));
    expect(await dist.balanceOf(user1.address)).eq(0);
    expect(await dist.stakedBalanceOf(insurer.address, user1.address)).eq(WAD.div(2));

    await dist.connect(user1).stake(insurer.address, MAX_UINT, user1.address);
    expect(await dist.totalStakedCollateral()).eq(WAD.div(2));

    await insurer.connect(user1).approve(dist.address, MAX_UINT);
    await dist.connect(user1).stake(insurer.address, WAD.div(2), user1.address);

    expect(await dist.stakedBalanceOf(insurer.address, user1.address)).eq(WAD);
    expect(await dist.totalStakedCollateral()).eq(WAD);

    await dist.connect(user1).stake(insurer.address, MAX_UINT, user1.address);

    await expect(dist.connect(user1).stake(insurer.address, WAD.div(2), user1.address)).revertedWith(
      'transfer amount exceeds balance'
    );
    await dist.connect(user1).stake(insurer.address, MAX_UINT, user1.address, testEnv.covGas());

    await dist.connect(user2).stake(insurer.address, WAD.div(2), user1.address, testEnv.covGas());
    await dist.connect(user2).stake(insurer.address, WAD.div(2), user2.address, testEnv.covGas());

    expect(await dist.totalStakedCollateral()).eq(WAD.mul(2));
    expect(await insurer.balanceOf(dist.address)).eq(WAD.mul(2));

    expect(await dist.balanceOf(user1.address)).eq(0);
    expect(await dist.balanceOf(user2.address)).eq(0);
    expect(await dist.stakedBalanceOf(insurer.address, user1.address)).eq(WAD.mul(3).div(2));
    expect(await dist.stakedBalanceOf(insurer.address, user2.address)).eq(WAD.div(2));

    await dist.connect(user2).unstake(insurer.address, WAD.div(2), user2.address, testEnv.covGas());
    expect(await dist.stakedBalanceOf(insurer.address, user2.address)).eq(0);
    expect(await insurer.balanceOf(user2.address)).eq(WAD.div(2));
    expect(await insurer.balanceOf(dist.address)).eq(WAD.mul(3).div(2));

    await expect(dist.connect(user2).unstake(insurer.address, WAD.div(2), user2.address)).reverted;
    await dist.connect(user2).unstake(insurer.address, MAX_UINT, user2.address, testEnv.covGas());
    expect(await insurer.balanceOf(user2.address)).eq(WAD.div(2));
    expect(await insurer.balanceOf(dist.address)).eq(WAD.mul(3).div(2));

    await dist.connect(user1).unstake(insurer.address, WAD.div(2), user2.address, testEnv.covGas());
    expect(await insurer.balanceOf(user2.address)).eq(WAD);
    expect(await insurer.balanceOf(dist.address)).eq(WAD);
    expect(await dist.stakedBalanceOf(insurer.address, user1.address)).eq(WAD);

    await dist.connect(user1).unstake(insurer.address, MAX_UINT, user1.address, testEnv.covGas());
    expect(await insurer.balanceOf(user1.address)).eq(WAD);
    expect(await insurer.balanceOf(dist.address)).eq(0);
    expect(await dist.stakedBalanceOf(insurer.address, user1.address)).eq(0);

    await dist.connect(user1).unstake(insurer.address, MAX_UINT, user1.address, testEnv.covGas());
  });

  it('Add/remove yield sources', async () => {
    const checkSource = async (address: string, rate: BigNumberish, sourceType: number): Promise<void> => {
      const info = await dist.getYieldSource(address);
      expect(info.sourceType).eq(sourceType);
      expect(info.expectedRate).eq(rate);
    };

    await checkSource(user2.address, 0, 0);
    await checkSource(user3.address, 0, 0);

    await expect(dist.addYieldPayout(0, WAD)).reverted;

    await dist.addYieldSource(user2.address, YieldSourceType.NullPull, testEnv.covGas());
    await checkSource(user2.address, 0, YieldSourceType.NullPull);
    await checkSource(user3.address, 0, 0);

    await dist.addYieldSource(user3.address, YieldSourceType.NullPull, testEnv.covGas());
    await checkSource(user2.address, 0, YieldSourceType.NullPull);
    await checkSource(user3.address, 0, YieldSourceType.NullPull);

    await dist.connect(user2).addYieldPayout(0, WAD.mul(2));
    await dist.connect(user3).addYieldPayout(0, WAD.mul(3));
    await checkSource(user2.address, WAD.mul(2), YieldSourceType.NullPull);
    await checkSource(user3.address, WAD.mul(3), YieldSourceType.NullPull);

    await dist.removeYieldSource(user2.address, testEnv.covGas());

    await checkSource(user2.address, 0, 0);
    await checkSource(user3.address, WAD.mul(3), YieldSourceType.NullPull);

    await dist.removeYieldSource(user2.address, testEnv.covGas()); // should not revert

    await dist.removeYieldSource(user3.address, testEnv.covGas());

    await checkSource(user2.address, 0, 0);
    await checkSource(user3.address, 0, 0);
  });

  it('Yield distribution for an insurer', async () => {
    await dist.connect(user1).stake(insurer.address, WAD, user1.address);
    await dist.connect(user2).stake(insurer.address, WAD.div(2), user2.address);
    expect(await dist.totalStakedCollateral()).eq(WAD.mul(3).div(2));

    await dist.addYieldSource(user3.address, YieldSourceType.Passive, testEnv.covGas());

    const rate = WAD.mul(3);
    await dist.connect(user3).addYieldPayout(0, rate);
    const startedAt = await currentTime();

    await increaseTime(100);

    if (!testEnv.underCoverage) {
      const stageT0 = await currentTime();
      const deltaT0 = stageT0 - startedAt;

      const y1 = await dist.balanceOf(user1.address);
      const y2 = await dist.balanceOf(user2.address);

      if (!testEnv.underCoverage) {
        expect(y1).eq(rate.mul(deltaT0 * 2).div(3));
        expect(y2).eq(rate.mul(deltaT0).div(3));
      }
    }

    await dist.connect(user1).unstake(insurer.address, WAD.div(2), user1.address, testEnv.covGas());
    expect(await dist.totalStakedCollateral()).eq(WAD);

    if (!testEnv.underCoverage) {
      const y1 = await dist.balanceOf(user1.address);
      const y2 = await dist.balanceOf(user2.address);
      const stageT0 = await currentTime();

      await increaseTime(100);
      const stageT1 = await currentTime();
      const deltaT1 = stageT1 - stageT0;

      expect((await dist.balanceOf(user1.address)).sub(y1)).eq(rate.mul(deltaT1).div(2));
      expect((await dist.balanceOf(user2.address)).sub(y2)).eq(rate.mul(deltaT1).div(2));
    }

    const y1 = await dist.balanceOf(user1.address);
    // there are no tokens available to claim yet ...
    await dist.connect(user1).claimYield(user1.address, testEnv.covGas());
    // TODO add an event and check it here

    if (!testEnv.underCoverage) {
      expect(await dist.balanceOf(user1.address)).eq(y1.add(rate.div(2)));
    }
  });

  it('Yield distribution for 2 insurers', async () => {
    const insurer1 = await Factories.MockInsurerForYield.deploy(cc.address);
    await cc.registerInsurer(insurer1.address);

    await insurer1.mint(user2.address, WAD);
    await insurer1.connect(user2).approve(dist.address, WAD);

    await dist.connect(user1).stake(insurer.address, WAD, user1.address, testEnv.covGas());
    await dist.connect(user2).stake(insurer1.address, WAD, user2.address, testEnv.covGas());
    await dist.connect(user2).stake(insurer.address, WAD, user2.address, testEnv.covGas());

    expect(await dist.totalStakedCollateral()).eq(WAD.mul(3));

    await dist.addYieldSource(user3.address, YieldSourceType.Passive, testEnv.covGas());

    const rate = WAD.mul(3);
    await dist.connect(user3).addYieldPayout(0, rate);
    const startedAt = await currentTime();

    await increaseTime(100);

    if (!testEnv.underCoverage) {
      const stageT0 = await currentTime();
      const deltaT0 = stageT0 - startedAt;

      const y1 = await dist.balanceOf(user1.address);
      const y2 = await dist.balanceOf(user2.address);

      expect(y1).eq(rate.mul(deltaT0).div(3));
      expect(y2).eq(rate.mul(deltaT0 * 2).div(3));
    }

    await insurer1.setCollateralSupplyFactor(WAD.div(2));
    await dist.syncStakeAsset(insurer1.address);
    expect(await dist.totalStakedCollateral()).eq(WAD.mul(5).div(2));
    expect(await dist.stakedBalanceOf(insurer1.address, user2.address)).eq(WAD);

    const checkBalances = async (rate1: BigNumber): Promise<void> => {
      if (testEnv.underCoverage) {
        return;
      }

      const y1 = await dist.balanceOf(user1.address);
      const y2 = await dist.balanceOf(user2.address);
      const stageT0 = await currentTime();

      await increaseTime(100);
      const stageT1 = await currentTime();
      const deltaT1 = stageT1 - stageT0;

      expect((await dist.balanceOf(user1.address)).sub(y1)).eq(rate1.mul(deltaT1));
      expect((await dist.balanceOf(user2.address)).sub(y2)).eq(rate.sub(rate1).mul(deltaT1));
    };

    await checkBalances(rate.mul(2).div(5));

    await dist.connect(user1).unstake(insurer.address, WAD.div(2), user1.address, testEnv.covGas());
    expect(await dist.totalStakedCollateral()).eq(WAD.mul(2));

    await checkBalances(rate.div(4));

    await dist.connect(user2).unstake(insurer.address, WAD.div(2), user2.address, testEnv.covGas());
    expect(await dist.totalStakedCollateral()).eq(WAD.mul(3).div(2));

    await checkBalances(rate.div(3));

    await dist.connect(user2).unstake(insurer1.address, WAD.div(2), user2.address, testEnv.covGas());
    expect(await dist.totalStakedCollateral()).eq(WAD.mul(5).div(4));
    expect(await dist.stakedBalanceOf(insurer1.address, user2.address)).eq(WAD.div(2));

    await checkBalances(rate.mul(2).div(5));

    await cc.unregister(insurer1.address, testEnv.covGas());
    expect(await dist.totalStakedCollateral()).eq(WAD);
    expect(await dist.stakedBalanceOf(insurer1.address, user2.address)).eq(WAD.div(2));

    await checkBalances(rate.div(2));
  });

  it('Yield payouts', async () => {
    await dist.connect(user1).stake(insurer.address, WAD, user1.address);

    await cc.registerLiquidityProvider(user0.address);
    await cc.mint(user3.address, RAY);
    await cc.connect(user3).approve(dist.address, MAX_UINT);

    await dist.addYieldSource(user3.address, YieldSourceType.Passive, testEnv.covGas());
    {
      const info = await dist.getYieldInfo();
      expect(info.rate).eq(0);
      expect(info.debt).eq(0);
    }

    const rate0 = WAD.mul(3);
    await dist.connect(user3).addYieldPayout(0, rate0);
    {
      const info = await dist.getYieldInfo();
      expect(info.rate).eq(rate0);
      expect(info.debt).eq(0);
    }

    const startedAt = await currentTime();
    increaseTime(10);

    const rate1 = WAD.mul(5);
    const paidOut0 = rate0.mul(3);
    await dist.connect(user3).addYieldPayout(paidOut0, rate1); // underpayment

    expect(await cc.balanceOf(dist.address)).eq(paidOut0);
    {
      const deltaT = (await currentTime()) - startedAt;
      const info = await dist.getYieldInfo();
      expect(info.rate).eq(rate1);
      if (!testEnv.underCoverage) {
        expect(info.debt).eq(rate0.mul(deltaT).sub(paidOut0));
      }
    }
    {
      const y1 = await dist.balanceOf(user1.address);
      expect(y1).gt(0);
      increaseTime(1);

      // there is no new payouts until the yield debt is covered
      expect(await dist.balanceOf(user1.address)).eq(y1);
    }

    expect(await cc.balanceOf(user1.address)).eq(0);
    await dist.connect(user1).claimYield(user1.address);

    expect(await cc.balanceOf(user1.address)).eq(paidOut0);
    expect(await dist.balanceOf(user1.address)).gt(0);
    expect(await cc.balanceOf(dist.address)).eq(0);

    const paidOut1 = rate0.mul(300);
    await dist.connect(user3).addYieldPayout(paidOut1, rate1); // overpayment

    expect(await cc.balanceOf(dist.address)).eq(paidOut1);
    {
      const info = await dist.getYieldInfo();
      expect(info.rate).eq(rate1);
      expect(info.debt).eq(0);
    }

    await dist.connect(user1).claimYieldFrom(user1.address, [insurer.address]);
    expect(await cc.balanceOf(dist.address)).eq(0);
    expect(await cc.balanceOf(user1.address)).eq(paidOut0.add(paidOut1));
  });
});