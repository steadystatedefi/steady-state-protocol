import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { HALF_RAY, RAY } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { CollateralCurrency, MockInsuredPool, MockImperpetualPool } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Imperpetual Index Pool', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 100000 * unitSize;
  let pool: MockImperpetualPool;
  const insureds: MockInsuredPool[] = [];
  const insuredUnits: number[] = [];
  const insuredTS: number[] = [];
  let cc: CollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
    const extension = await Factories.ImperpetualPoolExtension.deploy(unitSize);
    cc = await Factories.CollateralCurrency.deploy('Collateral', '$CC', 18);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockImperpetualPool.deploy(cc.address, unitSize, decimals, extension.address);
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
      // console.log('>>', coverage.totalDemand.toNumber(), coverage.totalCovered.add(coverage.pendingCovered).toNumber(), coverage.premiumRate.toNumber(), coverage.totalPremium.toNumber());
    }

    const totals = await pool.getTotals();
    // console.log('==', totals.coverage.totalDemand.toNumber(), totals.coverage.totalCovered.add(totals.coverage.pendingCovered).toNumber(), totals.coverage.premiumRate.toNumber(), totals.coverage.totalPremium.toNumber());

    expect(totalCovered).eq(totals.coverage.totalCovered);
    expect(totalDemand).eq(totals.coverage.totalDemand);
    // expect(totalPremium - 1).lte(totals.coverage.totalPremium); // rounding

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

    // console.log('::::: ', totalPremium - precisionMargin, totals.coverage.totalPremium.toNumber(), totalPremium + 1);
    // console.log('      ', totals.coverage.totalCovered.toString(), totals.coverage.pendingCovered.toString(), totals.coverage.premiumRate.toString(), await currentTime());
    expect(totals.coverage.totalPremium.toNumber()).within(
      totalPremium > precisionMargin ? totalPremium - precisionMargin : 0,
      totalPremium + 1
    );
  };

  const checkUserTotals = async () => {
    let total = await pool.totalSupply();
    const {
      coverage: { premiumRate: totalRate, totalPremium: totalInterest },
    } = await pool.getTotals();

    // console.log('\n>>>>', totalRatetOfUsers.toString(), totalInterestOfUsers.toString());
    for (const testUser of testEnv.users) {
      const balance = await pool.balanceOf(testUser.address);
      total = total.sub(balance);
    }
    // console.log('<<<<', totalRatetOfUsers.toString(), totalInterestOfUsers.toString());

    expect(total).eq(0);
    // expect(totalRate).eq(0);
    // expect(totalInterest).gte(0);
    // expect(totalInterest).lte((await currentTime()) - insuredTS[0]);
  };

  let totalCoverageProvidedUnits = 0;
  let totalInvested = 0;

  afterEach(async () => {
    if (testEnv.underCoverage) {
      return;
    }

    await advanceTimeAndBlock(10);

    await checkTotals();
    await checkUserTotals();
  });

  it('Add coverage by users', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    expect(await cc.balanceOf(pool.address)).eq(0);

    // let totalPremium = 0;
    // let totalPremiumRate = 0;

    let perUser = 400;
    for (const testUser of testEnv.users) {
      perUser += 100;
      totalCoverageProvidedUnits += perUser;
      userUnits.push(perUser);

      const investment = unitSize * perUser;
      totalInvested += investment;
      await cc.mintAndTransfer(testUser.address, pool.address, investment, {
        gasLimit: testEnv.underCoverage ? 2000000 : undefined,
      });
      timestamps.push(await currentTime());

      expect(await cc.balanceOf(pool.address)).eq(totalInvested);

      // const interest = await pool.interestOf(testUser.address);
      // expect(interest.accumulated).eq(0);
      // expect(interest.rate).eq(premiumPerUnit * perUser);

      const balance = await pool.balanceOf(testUser.address);
      expect(
        balance
          .mul(await pool.exchangeRate())
          .add(HALF_RAY)
          .div(RAY)
      ).eq(unitSize * perUser);

      if (!testEnv.underCoverage) {
        await checkTotals();
      }
    }

    {
      const totals = await pool.getTotals();
      expect(totals.coverage.premiumRate).eq(premiumPerUnit * totalCoverageProvidedUnits);
      expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(
        totalCoverageProvidedUnits * unitSize
      );
    }

    // for (let index = 0; index < testEnv.users.length; index++) {
    //   const { address } = testEnv.users[index];
    //   const balance = await pool.balanceOf(address);
    //   // const interest = await pool.interestOf(address);
    //   const time = await currentTime();

    //   expect(balance).eq(unitSize * userUnits[index]);
    //   // expect(interest.rate).eq(premiumPerUnit * userUnits[index]);
    //   // if (!testEnv.underCoverage) {
    //   //   expect(interest.accumulated).eq(interest.rate.mul(time - timestamps[index]));
    //   // }

    //   // totalPremium += interest.accumulated.toNumber();
    //   // totalPremiumRate += interest.rate.toNumber();
    // }

    // expect(totalPremium).gt(0);
    // {
    //   const totals = await pool.getTotals();
    //   expect(totals.coverage.totalPremium).eq(totalPremium);
    //   expect(totals.coverage.premiumRate).eq(totalPremiumRate);
    // }
  });

  it('Push excess coverage (1)', async () => {
    let totalCoverageDemandedUnits = 0;
    for (const unit of insuredUnits) {
      totalCoverageDemandedUnits += unit;
    }

    const missingCoverage = totalCoverageDemandedUnits - totalCoverageProvidedUnits;
    expect(await pool.getExcessCoverage()).eq(0);
    await cc.mintAndTransfer(user.address, pool.address, unitSize * missingCoverage, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += unitSize * missingCoverage;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.getExcessCoverage()).eq(0);

    const investment = unitSize * 1000;
    await cc.mintAndTransfer(user.address, pool.address, investment, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += investment;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.getExcessCoverage()).eq(investment);
  });
});
