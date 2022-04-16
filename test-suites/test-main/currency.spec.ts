import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

import { Factories } from '../../helpers/contract-types';
import { currentTime } from '../../helpers/runtime-utils';
import { CollateralCurrency, MockInsuredPool, MockWeightedPool } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Coverage Currency', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 10000 * unitSize;
  let pool: MockWeightedPool;
  const insureds: MockInsuredPool[] = [];
  const insuredUnits: number[] = [];
  const insuredTS: number[] = [];
  let cc: CollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    [user] = testEnv.users;
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    cc = await Factories.CollateralCurrency.deploy('Collateral', '$CC', 18);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockWeightedPool.deploy(cc.address, unitSize, decimals, extension.address);
    await cc.registerInsurer(pool.address);
  });

  enum InsuredStatus {
    Unknown,
    JoinCancelled,
    JoinRejected,
    JoinFailed,
    Declined,
    Joining,
    Accepted,
    Banned,
    NotApplicable,
  }

  it('Insurer and insured pools', async () => {
    const minUnits = 10;
    const riskWeight = 1000; // 10%

    const joinPool = async (riskWeightValue: number) => {
      const insured = await Factories.MockInsuredPool.deploy(
        cc.address,
        poolDemand,
        RATE,
        minUnits,
        riskWeightValue,
        decimals
      );
      await insured.joinPool(pool.address);
      insuredTS.push(await currentTime());
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await pool.receivableDemandedCoverage(insured.address);
      insureds.push(insured);
      return stats.coverage;
    };

    {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(4000 * unitSize); // limit this depends on default pool params
      insuredUnits.push(4000);
    }

    {
      const coverage = await joinPool(riskWeight / 10);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(1000 * unitSize); // lower weight, lower share
      insuredUnits.push(1000);
    }

    for (let i = 2; i > 0; i -= 1) {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(4000 * unitSize);
      insuredUnits.push(4000);
    }

    for (let i = 1; i > 0; i -= 1) {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(0); // pool limit for uncovered demand is reached
      insuredUnits.push(0);
    }
  });

  let totalCoverageProvidedUnits = 0;

  it('Add coverage by users', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    let totalPremium = 0;
    let totalPremiumRate = 0;

    let perUser = 400;
    for (let index = 0; index < testEnv.users.length; index += 1) {
      const testUser = testEnv.users[index];
      timestamps.push(await currentTime());
      perUser += 100;
      totalCoverageProvidedUnits += perUser;
      userUnits.push(perUser);

      await cc.mintAndTransfer(testUser.address, pool.address, unitSize * perUser, {
        gasLimit: testEnv.underCoverage ? 2000000 : undefined,
      });

      const interest = await pool.interestRate(testUser.address);
      expect(interest.accumulated).eq(0);
      expect(interest.rate).eq(premiumPerUnit * perUser);

      const balance = await pool.balanceOf(testUser.address);
      expect(balance).eq(unitSize * perUser);
    }

    {
      const totals = await pool.getTotals();
      expect(totals.coverage.premiumRate).eq(premiumPerUnit * totalCoverageProvidedUnits);
      expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(
        totalCoverageProvidedUnits * unitSize
      );
    }

    for (let index = 0; index < testEnv.users.length; index += 1) {
      const testUser = testEnv.users[index];
      const balance = await pool.balanceOf(testUser.address);
      const interest = await pool.interestRate(testUser.address);

      expect(balance).eq(unitSize * userUnits[index]);
      expect(interest.rate).eq(premiumPerUnit * userUnits[index]);
      if (!testEnv.underCoverage) {
        expect(interest.accumulated).eq(interest.rate.mul((await currentTime()) - timestamps[index] - 1));
      }

      totalPremium += interest.accumulated.toNumber();
      totalPremiumRate += interest.rate.toNumber();
    }

    expect(totalPremium).gt(0);
    {
      const totals = await pool.getTotals();
      expect(totals.coverage.totalPremium).eq(totalPremium);
      expect(totals.coverage.premiumRate).eq(totalPremiumRate);
    }
  });

  it('Push excess coverage', async () => {
    let totalCoverageDemandedUnits = 0;
    for (let index = 0; index < insuredUnits.length; index += 1) {
      const unit = insuredUnits[index];
      totalCoverageDemandedUnits += unit;
    }

    expect(await pool.withdrawable(user.address)).eq(0);
    await cc.mintAndTransfer(
      user.address,
      pool.address,
      unitSize * (totalCoverageDemandedUnits - totalCoverageProvidedUnits),
      {
        gasLimit: testEnv.underCoverage ? 2000000 : undefined,
      }
    );
    expect(await pool.withdrawable(user.address)).eq(0);

    await cc.mintAndTransfer(user.address, pool.address, unitSize * 10000, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });
    expect(await pool.withdrawable(user.address)).eq(unitSize * 10000);
  });

  it('Withdraw excess', async () => {
    const userBalance = await pool.balanceOf(user.address);
    const withdrawable = await pool.withdrawable(user.address);

    expect(await cc.balanceOf(user.address)).eq(0);
    await pool.connect(user).withdrawAll();

    expect(await pool.withdrawable(user.address)).eq(0);
    expect(await cc.balanceOf(user.address)).eq(withdrawable);
    expect(await pool.balanceOf(user.address)).eq(userBalance.sub(withdrawable));
  });

  it('Push more excess coverage', async () => {
    await cc.mintAndTransfer(user.address, pool.address, unitSize * 10000, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });
    expect(await pool.withdrawable(user.address)).eq(unitSize * 10000);
  });

  it('Use excess coverage', async () => {
    for (let index = 0; index < insureds.length; index += 1) {
      const insured = insureds[index];
      await insured.pushCoverageDemandTo(pool.address, unitSize * 10000);
    }

    expect(await pool.withdrawable(user.address)).eq(0);
  });
});
