import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { HALF_RAY, RAY } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { advanceTimeAndBlock, currentTime } from '../../helpers/runtime-utils';
import { MockCollateralCurrency, IInsurerPool, MockInsuredPool, MockImperpetualPool } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Imperpetual Index Pool (2)', (testEnv: TestEnv) => {
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let pool: MockImperpetualPool;
  let poolIntf: IInsurerPool;
  const insureds: MockInsuredPool[] = [];
  const insuredTS: number[] = [];
  let cc: MockCollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockImperpetualPool.deploy(extension.address, joinExtension.address);
    await cc.registerInsurer(pool.address);
    poolIntf = Factories.IInsurerPool.attach(pool.address);
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
    // const {
    //   coverage: { premiumRate: totalRate, totalPremium: totalInterest },
    // } = await pool.getTotals();

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

  it('Add coverage by users into an empty pool', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    expect(await cc.balanceOf(pool.address)).eq(0);

    let perUser = 400;
    for (const testUser of testEnv.users) {
      perUser += 100;
      totalCoverageProvidedUnits += perUser;
      userUnits.push(perUser);

      const investment = unitSize * perUser;
      totalInvested += investment;
      await cc.mintAndTransfer(testUser.address, pool.address, investment, 0, {
        gasLimit: testEnv.underCoverage ? 2000000 : undefined,
      });
      timestamps.push(await currentTime());

      expect(await cc.balanceOf(pool.address)).eq(totalInvested);

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
      expect(totals.coverage.premiumRate).eq(0);
      expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(0);
      const excess = await pool.getExcessCoverage();
      expect(excess).eq(totalCoverageProvidedUnits * unitSize);

      expect(await pool.totalSupplyValue()).eq(
        totals.coverage.totalCovered.add(totals.coverage.pendingCovered).add(totals.coverage.totalPremium).add(excess)
      );
    }
  });
});
