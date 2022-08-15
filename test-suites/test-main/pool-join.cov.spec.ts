import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { Ifaces } from '../../helpers/contract-ifaces';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { IInsurerPool, MockCollateralCurrencyStub, MockInsuredPool, MockPerpetualPool } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Pool joins', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 10000 * unitSize;
  let pool: MockPerpetualPool;
  let poolIntf: IInsurerPool;
  let fund: MockCollateralCurrencyStub;
  const insureds: MockInsuredPool[] = [];
  const insuredUnits: number[] = [];
  const insuredTS: number[] = [];

  before(async () => {
    fund = await Factories.MockCollateralCurrencyStub.deploy();
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, fund.address);
    const extension = await Factories.PerpetualPoolExtension.deploy(zeroAddress(), unitSize, fund.address);
    pool = await Factories.MockPerpetualPool.deploy(extension.address, joinExtension.address);
    poolIntf = Ifaces.IInsurerPool.attach(pool.address);
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
      const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
      const insured = await Factories.MockInsuredPool.deploy(
        fund.address,
        poolDemand,
        RATE,
        minUnits * unitSize,
        premiumToken.address
      );
      await pool.approveNextJoin(riskWeightValue);
      await insured.joinPool(pool.address, { gasLimit: 1000000 });
      insuredTS.push(await currentTime());
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      insureds.push(insured);
      // collector.registerProtocolTokens(protocol.address, [insured.address], [payInToken]);
      return stats.coverage;
    };

    {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(4000 * unitSize); // limit this depends on default pool params
      insuredUnits.push(4000);
    }

    {
      const coverage = await joinPool(riskWeight * 10);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(1000 * unitSize); // higher risk, lower share
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

  let totalCoverageProvidedUnits = 0;

  it('Add coverage by users', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    let totalPremium = 0;
    let totalPremiumRate = 0;

    let perUser = 4;
    for (const user of testEnv.users) {
      perUser += 1;
      totalCoverageProvidedUnits += perUser;
      userUnits.push(perUser);
      await fund
        .connect(user)
        .invest(pool.address, unitSize * perUser, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });

      timestamps.push(await currentTime());
      const interest = await pool.interestOf(user.address);
      if (!testEnv.underCoverage) {
        expect(interest.accumulated).eq(0);
      }
      expect(interest.rate).eq(premiumPerUnit * perUser);

      const balance = await pool.balanceOf(user.address);
      expect(balance).eq(unitSize * perUser);
    }

    {
      const totals = await pool.getTotals();
      expect(totals.coverage.premiumRate).eq(premiumPerUnit * totalCoverageProvidedUnits);
      expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(
        totalCoverageProvidedUnits * unitSize
      );
    }

    for (let index = 0; index < testEnv.users.length; index++) {
      const user = testEnv.users[index];
      const balance = await pool.balanceOf(user.address);
      const interest = await pool.interestOf(user.address);
      const time = await currentTime();

      expect(balance).eq(unitSize * userUnits[index]);
      expect(interest.rate).eq(premiumPerUnit * userUnits[index]);
      if (!testEnv.underCoverage) {
        expect(interest.accumulated).eq(interest.rate.mul(time - timestamps[index]));
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

  it('Check coverage per insured', async () => {
    let totalInsuredPremiumRate = 0;
    let totalInsuredPremium = 0;

    const totals = await pool.getTotals();
    const totalDemandUnits = totals.coverage.totalDemand.div(unitSize).toNumber();

    for (let index = 0; index < insureds.length; index++) {
      const insured = insureds[index];
      const { coverage } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      expect(coverage.totalDemand).eq(insuredUnits[index] * unitSize);

      const covered = coverage.totalCovered.add(coverage.pendingCovered);
      expect(coverage.premiumRate).eq(
        covered
          .mul(premiumPerUnit)
          .add(unitSize - 1)
          .div(unitSize)
      );
      expect(covered.toNumber()).approximately(
        (totalCoverageProvidedUnits * unitSize * insuredUnits[index]) / totalDemandUnits,
        1
      );

      {
        const timeDelta = (await currentTime()) - insuredTS[index];
        const balances = await insured.balancesOf(pool.address);

        // here demanded coverage is in use - so a protocol is charged at max
        expect(balances.rate).eq(coverage.totalDemand.mul(premiumPerUnit).div(unitSize));

        // NB! premium is charged for _demand_ added to guarantee sufficient flow of premium.
        // Using reconcillation will match it with actual coverage.
        // if (!testEnv.underCoverage) {
        expect(balances.premium).eq(balances.rate.mul(timeDelta));
        // }

        if (coverage.totalPremium.eq(0)) {
          expect(balances.premium).eq(0);
        } else {
          expect(balances.premium).gt(coverage.totalPremium);
        }

        expect(balances.rate).eq(await insured.totalSupply());

        const totalPremium = await insured.totalPremium();
        expect(balances.rate).eq(totalPremium.rate);
        expect(balances.premium).eq(totalPremium.accumulated);

        totalInsuredPremium += totalPremium.accumulated.toNumber();
        totalInsuredPremiumRate += totalPremium.rate.toNumber();
      }
    }
    expect(totalInsuredPremiumRate).eq(totalDemandUnits * premiumPerUnit);
    if (totalInsuredPremium === 0) {
      expect(0).gt(totals.coverage.premiumRate);
      expect(0).gt(totals.coverage.totalPremium);
    } else {
      expect(totalInsuredPremiumRate).gt(totals.coverage.premiumRate);
      expect(totalInsuredPremium).gt(totals.coverage.totalPremium);
    }

    // const payList = await collector.expectedPayAfter(protocol.address, 1);
    // expect(payList.length).eq(1);
    // expect(payList[0].token).eq(payInToken);
    // expect(totalInsuredPremiumRate).eq(payList[0].amount);
  });

  const checkTotals = async () => {
    let totalDemand = 0;
    let totalCovered = 0;
    let totalRate = 0;
    let totalPremium = 0;

    const premiumRates: {
      at: number;
      rate: number;
    }[] = [];

    for (const insured of insureds) {
      const { coverage } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      expect(coverage.totalDemand.toNumber()).gte(coverage.totalCovered.toNumber());
      totalCovered += coverage.totalCovered.toNumber();
      totalDemand += coverage.totalDemand.toNumber();
      totalRate += coverage.premiumRate.toNumber();
      totalPremium += coverage.totalPremium.toNumber();
      premiumRates.push({
        at: coverage.premiumUpdatedAt,
        rate: coverage.premiumRate.toNumber(),
      });
    }

    const totals = await pool.getTotals();
    expect(totalCovered).eq(totals.coverage.totalCovered);
    expect(totalDemand).eq(totals.coverage.totalDemand);

    let precisionMargin = Math.round(insureds.length / 2);

    // rounding may lead to a slightly higher sum of rates per insured
    expect(totals.coverage.premiumRate.toNumber()).within(totalRate - precisionMargin, totalRate);

    let i = 0;
    for (const rate of premiumRates) {
      if (rate.at !== 0) {
        const timeDelta = totals.coverage.premiumUpdatedAt - rate.at;
        expect(timeDelta).gte(0);
        totalPremium += timeDelta * rate.rate;
        precisionMargin += rate.at - insuredTS[i];
        i += 1;
      }
    }

    expect(totals.coverage.totalPremium.toNumber()).within(
      totalPremium > precisionMargin ? totalPremium - precisionMargin : 0,
      totalPremium + 1
    );
  };

  it('Check totals', async () => {
    await checkTotals();
  });

  it('Reconcile', async () => {
    for (const insured of insureds) {
      const { coverage: coverage0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      await insured.reconcileWithInsurers(0, 0);

      const { coverage } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      expect(coverage0.totalDemand).eq(coverage.totalDemand);
      expect(coverage0.totalCovered).eq(coverage.totalCovered);
      // console.log('after', insured.address, coverage.totalPremium.toNumber(), coverage.premiumRate.toNumber());

      {
        const balances = await insured.balancesOf(pool.address);

        // here demanded coverage is in use - so a protocol is charged at max
        expect(balances.rate).eq(coverage.totalDemand.mul(premiumPerUnit).div(unitSize));

        // NB! reconcillation match it with actual coverage.
        expect(balances.premium).eq(coverage.totalPremium);
        expect(balances.rate).eq(await insured.totalSupply());
        if (coverage.premiumRate.eq(0)) {
          expect(balances.rate).eq(0);
        } else {
          expect(balances.rate).gt(coverage.premiumRate);
        }

        const totalPremium = await insured.totalPremium();
        expect(balances.rate).eq(totalPremium.rate);
        expect(balances.premium).eq(totalPremium.accumulated);
      }
    }

    let totalInsuredPremium = 0;
    let totalInsuredPremiumRate = 0;
    let totalDemand = 0;
    let totalCovered = 0;

    for (const insured of insureds) {
      const { coverage } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      totalInsuredPremium += coverage.totalPremium.toNumber();
      totalInsuredPremiumRate += coverage.premiumRate.toNumber();

      expect(coverage.totalDemand.toNumber()).gte(coverage.totalCovered.toNumber());
      totalCovered += coverage.totalCovered.toNumber();
      totalDemand += coverage.totalDemand.toNumber();
    }

    const totals = await pool.getTotals();
    expect(totalCovered).eq(totals.coverage.totalCovered);
    expect(totalDemand).eq(totals.coverage.totalDemand);

    let n = totals.coverage.premiumRate.toNumber();
    expect(totalInsuredPremiumRate).within(n, n + insureds.length); // rounding up may give +1 per insured

    n = totals.coverage.totalPremium.toNumber();
    if (!testEnv.underCoverage) {
      expect(totalInsuredPremium).within(n, n + insureds.length * ((await currentTime()) - insuredTS[0] - 1));
    }
  });

  it('Check unknown users', async () => {
    for (const address of [zeroAddress(), createRandomAddress()]) {
      expect(await pool.balanceOf(address)).eq(0);
      expect(await pool.statusOf(address)).eq(InsuredStatus.Unknown);

      {
        const interest = await pool.interestOf(address);
        expect(interest.rate).eq(0);
        expect(interest.accumulated).eq(0);
      }

      {
        const balances = await pool.balancesOf(address);
        expect(balances.coverage).eq(0);
        expect(balances.scaled).eq(0);
        expect(balances.premium).eq(0);
      }
    }
  });
});
