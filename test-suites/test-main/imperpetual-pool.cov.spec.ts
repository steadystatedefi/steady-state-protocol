import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { HALF_RAY, RAY } from '../../helpers/constants';
import { Ifaces } from '../../helpers/contract-ifaces';
import { Factories } from '../../helpers/contract-types';
import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { MockCollateralCurrency, IInsurerPool, MockInsuredPool, MockImperpetualPool } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Imperpetual Index Pool', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 100000 * unitSize;
  const drawdownPct = 10; // 10% constant inside MockImperpetualPool
  let pool: MockImperpetualPool;
  let poolIntf: IInsurerPool;
  const insureds: MockInsuredPool[] = [];
  const insuredUnits: number[] = [];
  const insuredTS: number[] = [];
  let cc: MockCollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC', 18);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockImperpetualPool.deploy(cc.address, unitSize, extension.address);
    await cc.registerInsurer(pool.address);
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
      const insured = await Factories.MockInsuredPool.deploy(cc.address, poolDemand, RATE, minUnits * unitSize);
      await pool.approveNextJoin(riskWeightValue);
      await insured.joinPool(pool.address);
      insuredTS.push(await currentTime());
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await poolIntf.receivableDemandedCoverage(insured.address, 0);
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

  it('Add coverage by users', async () => {
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
      expect(totals.coverage.premiumRate).eq(premiumPerUnit * totalCoverageProvidedUnits);
      expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(
        totalCoverageProvidedUnits * unitSize
      );

      expect(await pool.totalSupplyValue()).eq(
        totals.coverage.totalCovered.add(totals.coverage.pendingCovered).add(totals.coverage.totalPremium)
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

  it('Add excess coverage', async () => {
    let totalCoverageDemandedUnits = 0;
    for (const unit of insuredUnits) {
      totalCoverageDemandedUnits += unit;
    }

    const missingCoverage = totalCoverageDemandedUnits - totalCoverageProvidedUnits;
    expect(await pool.getExcessCoverage()).eq(0);
    await cc.mintAndTransfer(user.address, pool.address, unitSize * missingCoverage, 0, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += unitSize * missingCoverage;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.getExcessCoverage()).eq(0);

    const investment = unitSize * 1000;
    await cc.mintAndTransfer(user.address, pool.address, investment, 0, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += investment;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.getExcessCoverage()).eq(investment);
  });

  it('Burn excess', async () => {
    expect(await cc.balanceOf(user.address)).eq(0);

    const userBalance = await pool.balanceOf(user.address);
    const withdrawable = await pool.getExcessCoverage();

    const premium0 = (await pool.getTotals()).coverage.totalPremium;
    const totalValue0 = await pool.totalSupplyValue();
    const totalSupply0 = await pool.totalSupply();

    const exchangeRate0 = await pool.exchangeRate();
    expect(totalValue0.mul(RAY).add(totalSupply0.div(2)).div(totalSupply0)).eq(exchangeRate0);

    await pool.connect(user).burnPremium(user.address, withdrawable, user.address, { gasLimit: 2000000 });

    const premiumDelta = (await pool.getTotals()).coverage.totalPremium.sub(premium0);
    expect(await pool.totalSupplyValue()).eq(totalValue0.add(premiumDelta).sub(withdrawable));

    // NB! the exchange rate applied inside burnPremium gets more premium due to block advancement on a mutable call
    const exchangeRateX = totalValue0.add(premiumDelta).mul(RAY).add(totalSupply0.div(2)).div(totalSupply0);

    totalInvested -= withdrawable.toNumber();
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.getExcessCoverage()).eq(0);
    expect(await cc.balanceOf(user.address)).eq(withdrawable);

    const balanceDelta = totalSupply0.sub(await pool.totalSupply());
    expect(balanceDelta).gt(0);
    expect(await pool.balanceOf(user.address)).eq(userBalance.sub(balanceDelta));

    expect(balanceDelta.mul(exchangeRateX).add(HALF_RAY).div(RAY)).eq(withdrawable);
  });

  it('Fails to cancel coverage without reconcillation', async () => {
    const insured = insureds[0];
    await expect(insured.cancelCoverage(zeroAddress(), 0)).revertedWith('must be reconciled');
  });

  let givenOutCollateral = 0;

  it('Reconcile before cancellation', async () => {
    const insured = insureds[0];
    expect(await cc.balanceOf(insured.address)).eq(0);

    const { availableCoverage: expectedCollateral } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    expect(expectedCollateral).gt(0);

    await insured.reconcileWithAllInsurers(); // required to cancel

    const receivedCollateral = await cc.balanceOf(insured.address);
    expect(receivedCollateral).eq(expectedCollateral.mul(100 - drawdownPct).div(100)); // drawdown withholded
    expect(receivedCollateral).eq(await insured.totalReceivedCollateral());
    expect(receivedCollateral.add(await cc.balanceOf(pool.address))).eq(totalInvested);

    await insured.reconcileWithAllInsurers(); // repeated call should do nothing

    expect(receivedCollateral).eq(await cc.balanceOf(insured.address));
    expect(receivedCollateral).eq(await insured.totalReceivedCollateral());

    givenOutCollateral += receivedCollateral.toNumber();
  });

  it('Cancel coverage of insured[0] (no payout)', async () => {
    expect(await cc.balanceOf(pool.address)).eq(totalInvested - givenOutCollateral);
    const totalSupply0 = await pool.totalSupply();

    const insured = insureds[0];
    const adj0 = await pool.getPendingAdjustments();

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    const totalValue0 = await pool.totalSupplyValue();

    const excessCoverage0 = await pool.getExcessCoverage();

    expect(
      totals0.totalCovered
        .add(totals0.pendingCovered)
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    ).eq(totals0.premiumRate);
    expect(
      stats0.totalCovered
        .add(stats0.pendingCovered)
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    ).eq(stats0.premiumRate);

    /** **************** */
    /* Cancel coverage */
    await insured.cancelCoverage(zeroAddress(), 0);
    /** **************** */
    /** **************** */

    // all collateral was taken back
    givenOutCollateral = 0;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await cc.balanceOf(insured.address)).eq(0);

    const excessCoverage = (await pool.getExcessCoverage()).sub(excessCoverage0);
    expect(excessCoverage).gte(stats0.totalCovered);
    expect(excessCoverage).lte(stats0.totalCovered.add(stats0.pendingCovered));

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    expect(await pool.totalSupply()).eq(totalSupply0);
    expect(await pool.totalSupplyValue()).eq(totalValue0.add(totals1.totalPremium).sub(totals0.totalPremium));

    expect(
      totals1.totalCovered
        .add(totals1.pendingCovered)
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    ).eq(totals1.premiumRate);

    expect(stats1.totalDemand).eq(0);
    expect(stats1.totalCovered).eq(0);
    expect(stats1.totalPremium).gte(stats0.totalPremium);
    expect(stats1.premiumRate).eq(0);
    expect(stats1.pendingCovered).eq(0);

    expect(totals0.totalDemand.sub(totals1.totalDemand)).eq(stats0.totalDemand);
    expect(totals0.totalCovered.sub(totals1.totalCovered)).eq(stats0.totalCovered);
    expect(totals0.premiumRate.sub(totals1.premiumRate)).lte(stats0.premiumRate);
    expect(totals0.premiumRate.sub(totals1.premiumRate)).eq(
      excessCoverage
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    );
    expect(totals0.totalPremium).lt(totals1.totalPremium);

    const adj1 = await pool.getPendingAdjustments();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
  });

  it('Cancel coverage of insured[1] (full payout)', async () => {
    expect(await cc.balanceOf(pool.address)).eq(totalInvested - givenOutCollateral);
    const totalSupply0 = await pool.totalSupply();

    const insured = insureds[1];

    await insured.reconcileWithAllInsurers(); // required to cancel

    const adj0 = await pool.getPendingAdjustments();

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    const totalValue0 = await pool.totalSupplyValue();

    const excessCoverage0 = await pool.getExcessCoverage();
    const receiver = createRandomAddress();
    const payoutAmount = stats0.totalCovered.toNumber();

    /** **************** */
    /* Cancel coverage */
    await insured.cancelCoverage(receiver, payoutAmount);
    /** **************** */
    /** **************** */

    expect(await cc.balanceOf(insured.address)).eq(0);
    expect(await cc.balanceOf(receiver)).eq(payoutAmount);

    givenOutCollateral += payoutAmount;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested - givenOutCollateral);

    const excessCoverage = (await pool.getExcessCoverage()).sub(excessCoverage0);
    expect(excessCoverage).gte(stats0.totalCovered.sub(payoutAmount));
    expect(excessCoverage).lte(stats0.totalCovered.sub(payoutAmount).add(stats0.pendingCovered));

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    expect(await pool.totalSupply()).eq(totalSupply0);
    expect(await pool.totalSupplyValue()).eq(
      totalValue0.add(totals1.totalPremium).sub(totals0.totalPremium).sub(payoutAmount)
    );

    expect(
      totals1.totalCovered
        .add(totals1.pendingCovered)
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    ).eq(totals1.premiumRate);

    expect(stats1.totalDemand).eq(0);
    expect(stats1.totalCovered).eq(0);
    expect(stats1.totalPremium).gte(stats0.totalPremium);
    expect(stats1.premiumRate).eq(0);
    expect(stats1.pendingCovered).eq(0);

    expect(totals0.totalDemand.sub(totals1.totalDemand)).eq(stats0.totalDemand);
    expect(totals0.totalCovered.sub(totals1.totalCovered)).eq(stats0.totalCovered);
    expect(totals0.premiumRate.sub(totals1.premiumRate)).lte(stats0.premiumRate);
    expect(totals0.premiumRate.sub(totals1.premiumRate)).eq(
      excessCoverage
        .add(payoutAmount)
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    );
    expect(totals0.totalPremium).lt(totals1.totalPremium);

    const adj1 = await pool.getPendingAdjustments();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
  });
});
