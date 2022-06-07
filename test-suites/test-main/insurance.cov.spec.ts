import { Wallet } from '@ethersproject/wallet';
import { expect } from 'chai';

import { RAY } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { tEthereumAddress } from '../../helpers/types';
import { MockCollateralCurrency, MockInsuredPool, MockPerpetualPool, PremiumCollector } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Pool joins', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 10000 * unitSize;
  let payInToken: tEthereumAddress;
  const protocol = Wallet.createRandom();
  let pool: MockPerpetualPool;
  let fund: MockCollateralCurrency;
  let collector: PremiumCollector;
  const insureds: MockInsuredPool[] = [];
  const insuredUnits: number[] = [];
  const insuredTS: number[] = [];

  before(async () => {
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    fund = await Factories.MockCollateralCurrency.deploy();
    pool = await Factories.MockPerpetualPool.deploy(fund.address, unitSize, decimals, extension.address);
    collector = await Factories.PremiumCollector.deploy();

    payInToken = createRandomAddress();
    await collector.setPremiumScale(payInToken, [fund.address], [RAY]);
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
        fund.address,
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
      collector.registerProtocolTokens(protocol.address, [insured.address], [payInToken]);
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
      expect(interest.accumulated).eq(0);
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
      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
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

    const payList = await collector.expectedPayAfter(protocol.address, 1);
    expect(payList.length).eq(1);
    expect(payList[0].token).eq(payInToken);
    expect(totalInsuredPremiumRate).eq(payList[0].amount);
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
      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
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
      const { coverage: coverage0 } = await pool.receivableDemandedCoverage(insured.address);
      await insured.reconcileWithAllInsurers();

      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
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
      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
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
});
