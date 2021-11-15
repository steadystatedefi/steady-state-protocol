import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { MockCollateralFund, MockInsuredPool, MockWeightedPool } from '../../types';
import { expect } from 'chai';
import { currentTime } from '../../helpers/runtime-utils';

makeSharedStateSuite('Pool joins', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 10000 * unitSize;
  let pool: MockWeightedPool;
  let fund: MockCollateralFund;
  let insureds: MockInsuredPool[] = [];
  let insuredUnits: number[] = [];

  before(async () => {
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    fund = await Factories.MockCollateralFund.deploy();
    pool = await Factories.MockWeightedPool.deploy(fund.address, unitSize, decimals, extension.address);
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

    const joinPool = async (riskWeight: number) => {
      const insured = await Factories.MockInsuredPool.deploy(
        fund.address,
        poolDemand,
        RATE,
        minUnits,
        riskWeight,
        decimals
      );
      await insured.joinPool(pool.address);
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await pool.receivableCoverageDemand(insured.address);
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

    for (let i = 2; i > 0; i--) {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(4000 * unitSize);
      insuredUnits.push(4000);
    }

    for (let i = 1; i > 0; i--) {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(0); // pool limit for uncovered demand is reached
      insuredUnits.push(0);
    }
  });

  it('Add coverage', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    let _perUser = 4;
    let totalCoverageProvidedUnits = 0;
    for (const user of testEnv.users) {
      timestamps.push(await currentTime());
      _perUser++;
      totalCoverageProvidedUnits += _perUser;
      userUnits.push(_perUser);
      await fund.connect(user).invest(pool.address, unitSize * _perUser);
      const interest = await pool.interestRate(user.address);
      expect(interest.accumulated).eq(0);
      expect(interest.rate).eq(premiumPerUnit * _perUser);

      const balance = await pool.balanceOf(user.address);
      expect(balance).eq(unitSize * _perUser);
    }

    {
      const totals = await pool.getTotals();
      expect(totals.coverage.premiumRate).eq(premiumPerUnit * totalCoverageProvidedUnits);
      expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(
        totalCoverageProvidedUnits * unitSize
      );
    }

    let totalPremium = 0;
    const ct = await currentTime();
    for (let index = 0; index < testEnv.users.length; index++) {
      const user = testEnv.users[index];
      const balance = await pool.balanceOf(user.address);
      const interest = await pool.interestRate(user.address);

      expect(balance).eq(unitSize * userUnits[index]);
      expect(interest.rate).eq(premiumPerUnit * userUnits[index]);
      expect(interest.accumulated).eq(interest.rate.mul(ct - timestamps[index] - 1));

      totalPremium += interest.accumulated.toNumber();
    }

    let totalDemandUnits = 0;
    expect(totalPremium).gt(0);
    {
      const totals = await pool.getTotals();
      expect(totals.coverage.totalPremium).eq(totalPremium);
      totalDemandUnits = totals.coverage.totalDemand.div(unitSize).toNumber();
    }

    for (let index = 0; index < insureds.length; index++) {
      const insured = insureds[index];
      const { coverage } = await pool.receivableCoverageDemand(insured.address);

      expect(coverage.totalDemand).eq(insuredUnits[index] * unitSize);
      const covered = coverage.totalCovered.add(coverage.pendingCovered).toNumber();
      expect(covered).approximately(
        (totalCoverageProvidedUnits * unitSize * insuredUnits[index]) / totalDemandUnits,
        1
      );
    }
  });
});
