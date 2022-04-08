import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { CollateralCurrency, MockInsuredPool, MockWeightedPool } from '../../types';
import { expect } from 'chai';
import { advanceTimeAndBlock, currentTime } from '../../helpers/runtime-utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { zeroAddress } from 'ethereumjs-util';

makeSharedStateSuite('Coverage cancels', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 100000 * unitSize;
  let pool: MockWeightedPool;
  let insureds: MockInsuredPool[] = [];
  let insuredUnits: number[] = [];
  let insuredTS: number[] = [];
  let cc: CollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
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

    const joinPool = async (riskWeight: number) => {
      const insured = await Factories.MockInsuredPool.deploy(
        cc.address,
        poolDemand,
        RATE,
        minUnits,
        riskWeight,
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
    //    return;
    await advanceTimeAndBlock(10);

    let totalDemand = 0;
    let totalCovered = 0;
    let totalRate = 0;
    let totalPremium = 0;

    let premiumRates: {
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
    for (const r of premiumRates) {
      if (r.at == 0) {
        continue;
      }
      const timeDelta = totals.coverage.premiumUpdatedAt - r.at;
      expect(timeDelta).gte(0);
      totalPremium += timeDelta * r.rate;
      precisionMargin += r.at - insuredTS[i++];
    }

    // console.log('::::: ', totalPremium - precisionMargin, totals.coverage.totalPremium.toNumber(), totalPremium + 1);
    // console.log('      ', totals.coverage.totalCovered.toString(), totals.coverage.pendingCovered.toString(), totals.coverage.premiumRate.toString(), await currentTime());
    expect(totals.coverage.totalPremium.toNumber()).within(
      totalPremium > precisionMargin ? totalPremium - precisionMargin : 0,
      totalPremium + 1
    );
  };

  afterEach(async () => {
    await checkTotals();
  });

  let totalCoverageProvidedUnits = 0;

  it('Add coverage by users', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    let totalPremium = 0;
    let totalPremiumRate = 0;

    let _perUser = 400;
    for (const user of testEnv.users) {
      timestamps.push(await currentTime());
      _perUser += 100;
      totalCoverageProvidedUnits += _perUser;
      userUnits.push(_perUser);

      await cc.mintAndTransfer(user.address, pool.address, unitSize * _perUser, {
        gasLimit: testEnv.underCoverage ? 2000000 : undefined,
      });

      const interest = await pool.interestRate(user.address);
      expect(interest.accumulated).eq(0);
      expect(interest.rate).eq(premiumPerUnit * _perUser);

      const balance = await pool.balanceOf(user.address);
      expect(balance).eq(unitSize * _perUser);

      await checkTotals();
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
      const interest = await pool.interestRate(user.address);

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

  it('Push excess coverage (1)', async () => {
    let totalCoverageDemandedUnits = 0;
    for (let u of insuredUnits) {
      totalCoverageDemandedUnits += u;
    }

    let missingCoverage = totalCoverageDemandedUnits - totalCoverageProvidedUnits;
    expect(await pool.withdrawable(user.address)).eq(0);
    await cc.mintAndTransfer(user.address, pool.address, unitSize * missingCoverage, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    expect(await pool.withdrawable(user.address)).eq(0);

    await cc.mintAndTransfer(user.address, pool.address, unitSize * 1000, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    expect(await pool.withdrawable(user.address)).eq(unitSize * 1000);
  });

  it('Withdraw excess', async () => {
    expect(await cc.balanceOf(user.address)).eq(0);

    const userBalance = await pool.balanceOf(user.address);
    const withdrawable = await pool.withdrawable(user.address);

    await pool.connect(user).withdrawAll({ gasLimit: 2000000 });

    expect(await pool.withdrawable(user.address)).eq(0);
    expect(await cc.balanceOf(user.address)).eq(withdrawable);
    expect(await pool.balanceOf(user.address)).eq(userBalance.sub(withdrawable));
  });

  it('Add unbalanced demand', async () => {
    const totals0 = await pool.getTotals();
    expect(totals0.total.openRounds).eq(0);
    expect(totals0.total.usableRounds).eq(0);

    await insureds[1].pushCoverageDemandTo(pool.address, unitSize * 50);

    const totals1 = await pool.getTotals();
    expect(totals1.total.openRounds).eq(50);
    expect(totals0.total.usableRounds).eq(0);
    expect(totals1.coverage.totalDemand).gt(totals0.coverage.totalDemand);
  });

  it('Add excess coverage, unusable due to unbalanced demand', async () => {
    expect(await pool.withdrawable(user.address)).eq(0);

    await cc.mintAndTransfer(user.address, pool.address, unitSize * 1000, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    expect(await pool.withdrawable(user.address)).eq(unitSize * 1000);
  });

  it('Add more demand, to make batches fragmented', async () => {
    const totals0 = await pool.getTotals();

    const excess = await pool.getExcessCoverage();
    await pool.setExcessCoverage(0);

    for (const insured of insureds) {
      await insured.pushCoverageDemandTo(pool.address, poolDemand);
    }
    await pool.setExcessCoverage(excess);

    const totals1 = await pool.getTotals();
    expect(totals0.total.batchCount).lt(totals1.total.batchCount);
  });

  // it('Check totals', async () => {
  //   for (const insured of insureds) {
  //     await insured.reconcileWithAllInsurers();
  //   }
  //   await checkTotals();
  //   // console.log(await pool.dumpInsured(insureds[0].address));
  // });

  it('Push the excess coverage (2)', async () => {
    // console.log('excessCoverage', (await pool.getExcessCoverage()).toString());
    await pool.pushCoverageExcess();
    expect(await pool.withdrawable(user.address)).eq(0);
  });

  // it('Receive', async () => {
  //   for (const insured of insureds) {
  //     await insured.reconcileWithAllInsurers();
  //   }
  //   await checkTotals();
  // });

  it('Fails to cancel coverage with coverage demand present', async () => {
    const insured = insureds[0];
    await expect(insured.cancelCoverage(zeroAddress(), 0)).revertedWith('demand must be cancelled');
  });

  it('Cancel coverage demand for insureds[0]', async () => {
    const insured = insureds[0];

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await pool.receivableDemandedCoverage(insured.address);

    await insured.testCancelCoverageDemand(pool.address, 1000000000);

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await pool.receivableDemandedCoverage(insured.address);

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

    const adj = await pool.getUnadjusted();
    expect(adj.pendingDemand.mul(unitSize)).eq(stats0.totalDemand.sub(stats1.totalDemand));
    expect(adj.pendingCovered).eq(0);
  });

  it('Repeat coverage demand cancellation for insureds[0]', async () => {
    const insured = insureds[0];

    const { coverage: stats0 } = await pool.receivableDemandedCoverage(insured.address);
    const adj0 = await pool.getUnadjusted();

    await insured.testCancelCoverageDemand(pool.address, 1000000000);

    const { coverage: stats1 } = await pool.receivableDemandedCoverage(insured.address);

    expect(stats0.totalCovered).eq(stats1.totalCovered);
    expect(stats0.premiumRate).eq(stats1.premiumRate);
    expect(stats0.pendingCovered).eq(stats1.pendingCovered);
    expect(stats0.totalDemand).eq(stats1.totalDemand);
    expect(stats0.totalPremium).lt(stats1.totalPremium);

    const adj1 = await pool.getUnadjusted();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
    expect(adj0.pendingCovered).eq(adj1.pendingCovered);
  });

  it('Fails to cancel coverage without reconcillation', async () => {
    const insured = insureds[0];
    await expect(insured.cancelCoverage(zeroAddress(), 0)).revertedWith(
      'coverage must be received before cancellation'
    );
  });

  it('Cancel coverage', async () => {
    const insured = insureds[0];
    const adj0 = await pool.getUnadjusted();

    await insured.reconcileWithAllInsurers(); // required for cancel

    const { coverage: totals0 } = await pool.getTotals();
    const { coverage: stats0 } = await pool.receivableDemandedCoverage(insured.address);

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

    await insured.cancelCoverage(zeroAddress(), 0);

    const excessCoverage = await pool.getExcessCoverage();
    expect(excessCoverage).gte(stats0.totalCovered);
    expect(excessCoverage).lte(stats0.totalCovered.add(stats0.pendingCovered));

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await pool.receivableDemandedCoverage(insured.address);

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

    const adj1 = await pool.getUnadjusted();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
    // TODO expect(adj0.pendingCovered).eq(stats0.totalCovered);
  });

  const callAndCheckTotals = async (fn: () => Promise<void>) => {
    const { coverage: totals0, total: internals0 } = await pool.getTotals();

    await fn();

    const { coverage: totals1, total: internals1 } = await pool.getTotals();

    expect(totals1.totalDemand).eq(totals0.totalDemand);
    expect(totals1.totalCovered).eq(totals0.totalCovered);
    expect(totals1.premiumRate).eq(totals0.premiumRate);
    expect(totals1.premiumRateUpdatedAt).gte(totals0.premiumRateUpdatedAt);
    if (totals0.premiumUpdatedAt != 0) {
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
    const { coverage: stats0 } = await pool.receivableDemandedCoverage(insured.address);

    await insured.testCancelCoverageDemand(pool.address, 1000000000);

    const adj0 = await pool.getUnadjusted();

    const { coverage: totals1 } = await pool.getTotals();
    const { coverage: stats1 } = await pool.receivableDemandedCoverage(insured.address);

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
    const dump = await pool.dump();
    expect(dump.batches[0].unitPerRound).gt(0);
    expect(dump.batches[1].unitPerRound).eq(0);
    expect(dump.batches[2].unitPerRound).gt(0);

    expect(dump.batches[1].rounds).eq(0);
    expect(dump.batches[1].roundPremiumRateSum).eq(0);
    expect(dump.batches[1].state).eq(1); // this zero round MUST remain "ready to use" to avoid lockup

    const adj1 = await pool.getUnadjusted();
    expect(adj0.pendingDemand).eq(adj1.pendingDemand);
    expect(adj0.pendingCovered).gt(0);
  });

  it('Push the excess released by cancellations', async () => {
    const { coverage: totals0 } = await pool.getTotals();
    const excessCoverage = await pool.getExcessCoverage();

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

  it('Check totals after reconcile', async () => {
    await callAndCheckTotals(async () => {
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

      for (const insured of insureds) {
        if ((await pool.statusOf(insured.address)) != InsuredStatus.Accepted) {
          continue;
        }

        const { coverage: stats0 } = await pool.receivableDemandedCoverage(insured.address);
        await insured.reconcileWithAllInsurers();
        const { coverage: stats1 } = await pool.receivableDemandedCoverage(insured.address);

        expect(stats1.totalDemand).eq(stats0.totalDemand);
        expect(stats1.totalCovered).eq(stats0.totalCovered);
        expect(stats1.premiumRate).eq(stats0.premiumRate);
        expect(stats1.premiumRateUpdatedAt).gte(stats0.premiumRateUpdatedAt);
        if (stats0.premiumUpdatedAt != 0) {
          expect(stats1.premiumUpdatedAt).gt(stats0.premiumUpdatedAt);
          expect(stats1.totalPremium).eq(
            stats0.totalPremium.add(stats0.premiumRate.mul(stats1.premiumUpdatedAt - stats0.premiumUpdatedAt))
          );
        }
      }
    });
  });

  it.skip('Apply delayed adjustments', async () => {
    await callAndCheckTotals(async () => {
      await pool.applyAdjustments();
    });
  });
});
