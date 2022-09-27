import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { MemberStatus } from '../../helpers/access-flags';
import { Factories } from '../../helpers/contract-types';
import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import {
  MockCollateralCurrency,
  IInsurerPool,
  MockInsuredPool,
  MockPerpetualPool,
  WeightedPoolExtension,
} from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Coverage cancel (with Perpetual Index Pool)', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemandUnits = 100000;
  const poolDemand = poolDemandUnits * unitSize;
  let pool: MockPerpetualPool;
  let poolIntf: IInsurerPool;
  let poolExt: WeightedPoolExtension;
  const insureds: MockInsuredPool[] = [];
  const insuredUnits: number[] = [];
  const insuredTS: number[] = [];
  let cc: MockCollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    const extension = await Factories.PerpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockPerpetualPool.deploy(extension.address, joinExtension.address);
    await cc.registerInsurer(pool.address);
    poolIntf = Factories.IInsurerPool.attach(pool.address);
    poolExt = Factories.WeightedPoolExtension.attach(pool.address);
  });

  const addInsured = async (minUnits: number, riskWeightValue: number, poolDemandValue: number) => {
    const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
    const insured = await Factories.MockInsuredPool.deploy(
      cc.address,
      poolDemandValue,
      RATE,
      minUnits * unitSize,
      premiumToken.address
    );
    await pool.approveNextJoin(riskWeightValue, premiumToken.address);
    await insured.joinPool(pool.address, { gasLimit: 1000000 });
    insuredTS.push(await currentTime());
    expect(await pool.statusOf(insured.address)).eq(MemberStatus.Accepted);
    const { 0: generic, 1: chartered } = await insured.getInsurers();
    expect(generic).eql([]);
    expect(chartered).eql([pool.address]);

    const stats = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    insureds.push(insured);
    return stats.coverage;
  };

  it('Insurer and insured pools', async () => {
    const minUnits = 10;
    const riskWeight = 1000; // 10%

    const joinPool = async (riskWeightValue: number) => addInsured(minUnits, riskWeightValue, poolDemand);

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
      insuredUnits.push(coverage.totalDemand.div(unitSize).toNumber());
    }

    for (let i = 2; i > 0; i--) {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(4000 * unitSize);
      insuredUnits.push(coverage.totalDemand.div(unitSize).toNumber());
    }

    for (let i = 1; i > 0; i--) {
      const coverage = await joinPool(riskWeight);
      expect(coverage.totalCovered).eq(0);
      expect(coverage.totalDemand).eq(0); // pool limit for uncovered demand is reached
      insuredUnits.push(coverage.totalDemand.div(unitSize).toNumber());
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
    let totalValue = await pool.totalSupplyValue();
    let {
      coverage: { premiumRate: totalRate, totalPremium: totalInterest },
    } = await pool.getTotals();

    // console.log('\n>>>>', totalRatetOfUsers.toString(), totalInterestOfUsers.toString());
    for (const testUser of testEnv.users) {
      const { value, balance, swappable: premium } = await pool.balancesOf(testUser.address);
      total = total.sub(balance);
      totalValue = totalValue.sub(value);

      const interest = await pool.interestOf(testUser.address);
      totalRate = totalRate.sub(interest.rate);
      totalInterest = totalInterest.sub(interest.accumulated);
      expect(premium).eq(interest.accumulated);
      // console.log('    ', interest.rate.toString(), interest.accumulated.toString());
    }
    // console.log('<<<<', totalRatetOfUsers.toString(), totalInterestOfUsers.toString());

    expect(total).eq(0);
    expect(totalValue).eq(0);
    expect(totalRate).eq(0);
    expect(totalInterest).gte(0);
    expect(totalInterest).lte((await currentTime()) - insuredTS[0]);
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

    let totalPremium = 0;
    let totalPremiumRate = 0;

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

      const interest = await pool.interestOf(testUser.address);
      expect(interest.accumulated).eq(0);
      expect(interest.rate).eq(premiumPerUnit * perUser);

      const balance = await pool.balanceOf(testUser.address);
      expect(balance).eq(unitSize * perUser);

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

    for (let index = 0; index < testEnv.users.length; index++) {
      const { address } = testEnv.users[index];
      const balance = await pool.balanceOf(address);
      const interest = await pool.interestOf(address);
      const time = await currentTime();

      expect(balance).eq(unitSize * userUnits[index]);
      expect(interest.rate).eq(premiumPerUnit * userUnits[index]);
      if (!testEnv.underCoverage) {
        expect(interest.accumulated).eq(interest.rate.mul(time - timestamps[index]));
      }

      totalPremium += interest.accumulated.toNumber();
      totalPremiumRate += interest.rate.toNumber();

      expect(await pool.statusOf(address)).eq(MemberStatus.NotApplicable);
    }

    expect(totalPremium).gt(0);
    {
      const totals = await pool.getTotals();
      expect(totals.coverage.totalPremium).eq(totalPremium);
      expect(totals.coverage.premiumRate).eq(totalPremiumRate);
    }
  });

  it('Add excess coverage', async () => {
    let totalCoverageDemandedUnits = 0;
    for (const unit of insuredUnits) {
      totalCoverageDemandedUnits += unit;
    }

    const missingCoverage = totalCoverageDemandedUnits - totalCoverageProvidedUnits;
    expect(await pool.withdrawable(user.address)).eq(0);
    await cc.mintAndTransfer(user.address, pool.address, unitSize * missingCoverage, 0, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += unitSize * missingCoverage;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.withdrawable(user.address)).eq(0);

    const investment = unitSize * 1000;
    await cc.mintAndTransfer(user.address, pool.address, investment, 0, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += investment;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.withdrawable(user.address)).eq(unitSize * 1000);
    expect(await pool.withdrawable(zeroAddress())).eq(0);
  });

  it('Withdraw excess', async () => {
    expect(await cc.balanceOf(user.address)).eq(0);

    const userBalance = await pool.balanceOf(user.address);
    const withdrawable = await pool.withdrawable(user.address);

    await pool.connect(user).withdrawAll({ gasLimit: 2000000 });

    expect(await pool.withdrawable(user.address)).eq(0);
    expect(await cc.balanceOf(user.address)).eq(withdrawable);
    expect(await pool.balanceOf(user.address)).eq(userBalance.sub(withdrawable));

    totalInvested -= withdrawable.toNumber();
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);
  });

  it('Add unbalanced demand', async () => {
    const totals0 = await pool.getTotals();
    expect(totals0.total.openRounds).eq(0);
    expect(totals0.total.usableRounds).eq(0);

    await insureds[1].pushCoverageDemandTo([pool.address], [unitSize * 50]);

    const totals1 = await pool.getTotals();
    expect(totals1.total.openRounds).eq(50);
    expect(totals0.total.usableRounds).eq(0);
    expect(totals1.coverage.totalDemand).gt(totals0.coverage.totalDemand);
  });

  it('Add excess coverage, unusable due to imbalanced demand', async () => {
    expect(await pool.withdrawable(user.address)).eq(0);

    const investment = unitSize * 1000;
    await cc.mintAndTransfer(user.address, pool.address, investment, 0, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    totalInvested += investment;
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    expect(await pool.withdrawable(user.address)).eq(unitSize * 1000);
  });

  it('Add more demand, to make batches fragmented', async () => {
    const totals0 = await pool.getTotals();

    const excess = await pool.getExcessCoverage();
    await pool.setExcessCoverage(0);

    for (const insured of insureds) {
      await insured.pushCoverageDemandTo([pool.address], [poolDemand]);
    }
    await pool.setExcessCoverage(excess);

    const totals1 = await pool.getTotals();
    expect(totals0.total.batchCount).lt(totals1.total.batchCount);
  });

  it('Push excess coverage', async () => {
    await pool.pushCoverageExcess();
    expect(await pool.withdrawable(user.address)).eq(0);
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    await pool.pushCoverageExcess(); // repeated call should do nothing
    expect(await pool.withdrawable(user.address)).eq(0);
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);
  });

  it('Fails to cancel coverage with coverage demand present', async () => {
    const insured = insureds[0];
    await expect(insured.cancelCoverage(zeroAddress(), 0)).revertedWith(testEnv.covReason('DemandMustBeCancelled()'));
  });

  it('Cancel coverage demand for insureds[0]', async () => {
    const insured = insureds[0];

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    await insured.testCancelCoverageDemand(pool.address, 1000000000);

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    expect(stats0.totalCovered).eq(stats1.totalCovered);
    expect(stats0.premiumRate).eq(stats1.premiumRate);
    expect(stats0.totalPremium).lte(stats1.totalPremium);
    expect(stats0.pendingCovered).eq(stats1.pendingCovered);

    expect(totals0.totalCovered).eq(totals1.totalCovered);
    expect(totals0.premiumRate).eq(totals1.premiumRate);
    expect(totals0.totalPremium).lte(totals1.totalPremium);
    expect(totals0.pendingCovered).eq(totals1.pendingCovered);

    expect(stats0.totalDemand).gte(stats0.totalCovered);
    expect(stats0.totalDemand).gt(stats1.totalDemand);
    expect(totals0.totalDemand.sub(totals1.totalDemand)).eq(stats0.totalDemand.sub(stats1.totalDemand));

    const adj = await poolExt.getPendingAdjustments();
    expect(adj.pendingDemand.mul(unitSize)).eq(stats0.totalDemand.sub(stats1.totalDemand));
    expect(adj.pendingCovered).eq(0);

    expect(await cc.balanceOf(pool.address)).eq(totalInvested);
  });

  it('Repeat coverage demand cancellation for insureds[0]', async () => {
    const insured = insureds[0];

    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    const adj0 = await poolExt.getPendingAdjustments();

    await insured.testCancelCoverageDemand(pool.address, 1000000000);

    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    expect(stats0.totalCovered).eq(stats1.totalCovered);
    expect(stats0.premiumRate).eq(stats1.premiumRate);
    expect(stats0.pendingCovered).eq(stats1.pendingCovered);
    expect(stats0.totalDemand).eq(stats1.totalDemand);

    if (!testEnv.underCoverage) {
      expect(stats0.totalPremium).lt(stats1.totalPremium);
    }

    const adj1 = await poolExt.getPendingAdjustments();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
    expect(adj0.pendingCovered).eq(adj1.pendingCovered);
  });

  it('Fails to cancel coverage without reconcillation', async () => {
    const insured = insureds[0];
    await expect(insured.cancelCoverage(zeroAddress(), 0)).revertedWith('must be reconciled');
  });

  it('Cancel coverage', async () => {
    expect(await pool.totalSupplyValue()).eq(totalInvested);

    const insured = insureds[0];
    const adj0 = await poolExt.getPendingAdjustments();

    expect(await cc.balanceOf(insured.address)).eq(0);

    {
      const {
        availableCoverage: expectedCollateral,
        coverage: { totalCovered: expectedCoverage },
      } = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      expect(expectedCollateral).gt(0);

      await insured.reconcileWithInsurers(0, 0); // required to cancel

      const receivedCollateral = await cc.balanceOf(insured.address);
      expect(receivedCollateral).eq(expectedCollateral);
      expect(receivedCollateral.add(await cc.balanceOf(pool.address))).eq(totalInvested);

      const totalReceived = await insured.totalReceived();
      expect(expectedCoverage).eq(totalReceived.receivedCoverage);
      expect(expectedCollateral).eq(totalReceived.receivedCollateral);
    }

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

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

    expect(await pool.getExcessCoverage()).eq(0);

    /** **************** */
    /* Cancel coverage */
    await insured.cancelCoverage(zeroAddress(), 0);
    /** **************** */
    /** **************** */

    expect(await cc.balanceOf(pool.address)).eq(totalInvested);
    expect(await cc.balanceOf(insured.address)).eq(0);

    expect(await pool.totalSupplyValue()).eq(totalInvested);

    const excessCoverage = await pool.getExcessCoverage();
    expect(excessCoverage).gte(stats0.totalCovered);
    expect(excessCoverage).lte(stats0.totalCovered.add(stats0.pendingCovered));

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

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

    const adj1 = await poolExt.getPendingAdjustments();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
    // TODO expect(adj0.pendingCovered).eq(stats0.totalCovered);
  });

  const callAndCheckTotals = async (fn: () => Promise<void>) => {
    const { coverage: totals0, total: internals0 } = await pool.getTotals();

    await fn();

    const { coverage: totals1, total: internals1 } = await pool.getTotals();

    if (testEnv.underCoverage) {
      return;
    }

    expect(totals1.totalDemand).eq(totals0.totalDemand);
    expect(totals1.totalCovered).eq(totals0.totalCovered);
    expect(totals1.premiumRate).eq(totals0.premiumRate);
    expect(totals1.premiumRateUpdatedAt).gte(totals0.premiumRateUpdatedAt);
    if (totals0.premiumUpdatedAt !== 0) {
      expect(totals1.premiumUpdatedAt).gt(totals0.premiumUpdatedAt);
      expect(totals1.totalPremium).eq(
        totals0.totalPremium.add(totals0.premiumRate.mul(totals1.premiumUpdatedAt - totals0.premiumUpdatedAt))
      );
    }

    expect(internals0.batchCount).eq(internals1.batchCount);
    expect(internals0.openRounds).eq(internals1.openRounds);
    expect(internals0.usableRounds).eq(internals1.usableRounds);
    expect(internals0.totalCoverable).eq(internals1.totalCoverable);
  };

  it('Cancel coverage demand for insureds[1] to create an inlined zero batch', async () => {
    const insured = insureds[1];

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    await insured.testCancelCoverageDemand(pool.address, 1000000000);

    const adj0 = await poolExt.getPendingAdjustments();

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    expect(stats0.totalCovered).eq(stats1.totalCovered);
    expect(stats0.premiumRate).eq(stats1.premiumRate);
    expect(stats0.totalPremium).lte(stats1.totalPremium);
    expect(stats0.pendingCovered).eq(stats1.pendingCovered);

    expect(totals0.totalCovered).eq(totals1.totalCovered);
    expect(totals0.premiumRate).eq(totals1.premiumRate);
    expect(totals0.totalPremium).lte(totals1.totalPremium);
    expect(totals0.pendingCovered).eq(totals1.pendingCovered);

    expect(stats0.totalDemand).gte(stats0.totalCovered);
    expect(stats0.totalDemand).gt(stats1.totalDemand);
    expect(totals0.totalDemand.sub(totals1.totalDemand)).eq(stats0.totalDemand.sub(stats1.totalDemand));

    // check for an inlined zero batch
    const dump = await poolExt.dumpBatches();
    expect(dump.batches[0].unitPerRound).gt(0);
    expect(dump.batches[1].unitPerRound).eq(0);
    expect(dump.batches[2].unitPerRound).gt(0);

    expect(dump.batches[0].rounds).gt(0);
    expect(dump.batches[2].rounds).gt(0);

    expect(dump.batches[1].rounds).eq(0);
    expect(dump.batches[1].roundPremiumRateSum).eq(0);
    expect(dump.batches[1].state).eq(1); // this zero round MUST remain "ready to use" to avoid lockup

    const adj1 = await poolExt.getPendingAdjustments();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
    expect(adj0.pendingCovered).gt(0);
  });

  it('Re-add from insured[1] and cancel it again to ensure that a zero batch behaves correctly', async () => {
    const insured = insureds[1];

    const { coverage: totals0 } = await pool.getTotals();
    const dump0 = await poolExt.dumpBatches();

    expect(dump0.batches[1].unitPerRound).eq(0);

    const excessCoverage = await pool.getExcessCoverage();
    await pool.setExcessCoverage(0);

    await insured.pushCoverageDemandTo([pool.address], [poolDemand]);

    await pool.setExcessCoverage(excessCoverage);

    const { coverage: totals1 } = await pool.getTotals();
    expect(totals1.totalDemand).gt(totals0.totalDemand);

    {
      const dump1 = await poolExt.dumpBatches();
      expect(dump1.batches[1].unitPerRound).gt(0);

      expect(dump1.batchCount).eq(dump0.batchCount);
      expect(dump1.batches.length).eq(dump0.batches.length);
      dump0.batches.forEach((b0, index) => {
        const b1 = dump1.batches[index];
        // make sure that batch chain remains unchanged
        expect(b0.nextBatchNo).eq(b1.nextBatchNo);
      });
    }

    await insured.testCancelCoverageDemand(pool.address, poolDemandUnits);

    {
      const dump1 = await poolExt.dumpBatches();

      dump0.batches.forEach((b0, index) => {
        const b1 = dump1.batches[index];
        expect(b0.nextBatchNo).eq(b1.nextBatchNo);
        expect(b0.roundPremiumRateSum).eq(b1.roundPremiumRateSum);
        expect(b0.rounds).eq(b1.rounds);
        expect(b0.unitPerRound).eq(b1.unitPerRound);
        expect(b0.state).eq(b1.state);
        // totalUnitsBeforeBatch is lazy for non-covered demand and cant be compared
        // expect(b0.totalUnitsBeforeBatch).eq(b1.totalUnitsBeforeBatch);
      });
    }
  });

  it('Push the excess released by cancellations', async () => {
    const { coverage: totals0 } = await pool.getTotals();
    const excessCoverage = await pool.getExcessCoverage();
    expect(excessCoverage).gt(0);

    await pool.pushCoverageExcess();

    const { coverage: totals1 } = await pool.getTotals();
    expect(await pool.getExcessCoverage()).eq(0);

    expect(totals1.premiumRateUpdatedAt).gt(totals0.premiumRateUpdatedAt);
    expect(totals1.premiumUpdatedAt).gt(totals0.premiumUpdatedAt);
    expect(totals1.totalDemand).eq(totals0.totalDemand);
    expect(totals1.totalCovered.add(totals1.pendingCovered).sub(totals0.totalCovered.add(totals0.pendingCovered))).eq(
      excessCoverage
    );
    expect(totals1.premiumRate.sub(totals0.premiumRate)).eq(
      excessCoverage
        .mul(premiumPerUnit)
        .add(unitSize / 2)
        .div(unitSize)
    );
    expect(totals1.totalPremium).gt(totals0.totalPremium);
  });

  let receivedCollateral = 0;

  it('Check totals after reconcile', async () => {
    expect(await cc.balanceOf(pool.address)).eq(totalInvested);

    await callAndCheckTotals(async () => {
      for (const insured of insureds) {
        const status = await pool.statusOf(insured.address);

        if (status !== MemberStatus.Accepted) {
          continue;
        }

        expect(await cc.balanceOf(insured.address)).eq(0);

        const { coverage: stats0, availableCoverage: expectedCollateral } = await poolIntf.receivableDemandedCoverage(
          insured.address,
          0
        );
        await insured.reconcileWithInsurers(0, 0);
        const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

        expect(await cc.balanceOf(insured.address)).eq(expectedCollateral);
        receivedCollateral += expectedCollateral.toNumber();

        expect(stats1.totalDemand).eq(stats0.totalDemand);
        expect(stats1.totalCovered).eq(stats0.totalCovered);
        expect(stats1.premiumRate).eq(stats0.premiumRate);
        expect(stats1.premiumRateUpdatedAt).gte(stats0.premiumRateUpdatedAt);

        if (testEnv.underCoverage) {
          continue;
        }

        if (stats0.premiumUpdatedAt !== 0) {
          expect(stats1.premiumUpdatedAt).gt(stats0.premiumUpdatedAt);
          expect(stats1.totalPremium).eq(
            stats0.totalPremium.add(stats0.premiumRate.mul(stats1.premiumUpdatedAt - stats0.premiumUpdatedAt))
          );
        }
      }
    });

    expect(await cc.balanceOf(pool.address)).eq(totalInvested - receivedCollateral);
  });

  it('Apply delayed adjustments', async () => {
    await callAndCheckTotals(async () => {
      await poolExt.applyPendingAdjustments();
    });

    const adj0 = await poolExt.getPendingAdjustments();
    expect(adj0.pendingDemand).eq(0);
    expect(adj0.pendingCovered).eq(0);
  });

  it('Cancel coverage for insureds[1] with partial repayment', async () => {
    expect(await pool.totalSupplyValue()).eq(totalInvested);

    const insured = insureds[1];

    await insured.reconcileWithInsurers(0, 0); // required to cancel

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    // collateral will be returned from the insured
    receivedCollateral -= (await cc.balanceOf(insured.address)).toNumber();

    expect(await pool.getExcessCoverage()).eq(0);

    const receiver = createRandomAddress();
    const payoutAmount = stats0.totalCovered.sub(stats0.totalCovered.div(4)).toNumber();

    const ptSupply0 = await pool.totalSupplyValue();
    expect(ptSupply0).eq(totalInvested);

    /** **************** */
    /* Cancel coverage */
    await insured.cancelCoverage(receiver, payoutAmount);
    /** **************** */
    /** **************** */

    expect(await pool.totalSupplyValue()).eq(totalInvested - payoutAmount);
    totalInvested -= payoutAmount;

    expect(await cc.balanceOf(insured.address)).eq(0);
    expect(await cc.balanceOf(receiver)).eq(payoutAmount);
    expect(await cc.balanceOf(pool.address)).eq(totalInvested - receivedCollateral);

    const excessCoverage = await pool.getExcessCoverage();
    expect(excessCoverage).gte(stats0.totalCovered.sub(payoutAmount));
    expect(excessCoverage).lte(stats0.totalCovered.sub(payoutAmount).add(stats0.pendingCovered));

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

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
  });

  it('Cancel coverage for insureds[2] with full repayment', async () => {
    expect(await pool.totalSupplyValue()).eq(totalInvested);

    const insured = insureds[2];

    await insured.reconcileWithInsurers(0, 0); // required to cancel

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    // collateral will be returned from the insured
    receivedCollateral -= (await cc.balanceOf(insured.address)).toNumber();

    const excessCoverage0 = await pool.getExcessCoverage();

    const receiver = createRandomAddress();
    const payoutAmount = stats0.totalCovered.toNumber();

    const ptSupply0 = await pool.totalSupplyValue();
    expect(ptSupply0).eq(totalInvested);

    /** **************** */
    /* Cancel coverage */
    await insured.cancelCoverage(receiver, payoutAmount);
    /** **************** */
    /** **************** */

    expect(await pool.totalSupplyValue()).eq(totalInvested - payoutAmount);

    expect(await cc.balanceOf(insured.address)).eq(0);
    expect(await cc.balanceOf(receiver)).eq(payoutAmount);
    expect(await cc.balanceOf(pool.address)).eq(totalInvested - receivedCollateral - payoutAmount);

    const excessCoverage = (await pool.getExcessCoverage()).sub(excessCoverage0);
    expect(excessCoverage).gte(stats0.totalCovered.sub(payoutAmount));
    expect(excessCoverage).lte(stats0.totalCovered.sub(payoutAmount).add(stats0.pendingCovered));

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

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
  });

  // TODO check premium rates after partial cancel
});
