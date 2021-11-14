import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { createRandomAddress, currentTime, increaseTime } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { MockWeightedRounds } from '../../types';
import { tEthereumAddress } from '../../helpers/types';
import { expect } from 'chai';
import { stringifyArgs } from '../../helpers/etherscan-verification';
import { BigNumber } from 'ethers';

makeSharedStateSuite('Weighted Rounds', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const ratePerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let subj: MockWeightedRounds;
  let insured1: tEthereumAddress;
  let insured2: tEthereumAddress;
  let insured3: tEthereumAddress;

  let totalPremium = BigNumber.from(0);
  let totalPremiumRate = BigNumber.from(0);
  let totalPremiumAt = 0;
  let overrides = { gasLimit: undefined as undefined | number };

  before(async () => {
    if (testEnv.underCoverage) {
      overrides.gasLimit = 1000000;
    }

    subj = await Factories.MockWeightedRounds.deploy(unitSize);
    await subj.setRoundLimits(1, 2, 3);
    insured1 = createRandomAddress();
    insured2 = createRandomAddress();
    insured3 = createRandomAddress();

    await subj.addInsured(insured1);
    await subj.addInsured(insured2);
    await subj.addInsured(insured3);
  });

  const dumpState = async () => {
    const dump = await subj.dump();
    console.log(
      'batchCount:',
      dump.batchCount.toNumber(),
      '\tlatestBatch:',
      dump.latestBatch.toNumber(),
      '\tfirstOpen:',
      dump.firstOpenBatch.toNumber(),
      'partialBatch:',
      dump.part.batchNo.toNumber(),
      'partialRound:',
      dump.part.roundNo,
      'partialRoundCoverage:',
      dump.part.roundCoverage.toString()
    );
    console.log(`batches (${dump.batches.length}):\n`, stringifyArgs(dump.batches));
  };

  type CoverageInfo = {
    totalDemand: BigNumber;
    totalCovered: BigNumber;
    pendingCovered: BigNumber;
    premiumRate: BigNumber;
    totalPremium: BigNumber;
    premiumUpdatedAt: number;
  };

  const expectCoverage = async (
    insured: tEthereumAddress,
    demand: number,
    covered: number,
    pending: number
  ): Promise<CoverageInfo> => {
    // console.log('====getCoverage', demand);
    const tt = await subj.receivableCoverageDemand(insured);
    const t = tt.coverage;
    expect(t.pendingCovered).eq(pending);
    expect(t.totalCovered).eq(covered * unitSize);
    expect(t.totalDemand).eq(demand * unitSize);
    expect(t.premiumRate).eq(covered * ratePerUnit + (pending * ratePerUnit) / unitSize);
    return t;
  };

  const checkTotals = async (...parts: CoverageInfo[]) => {
    // console.log('====getTotals');
    const tt = await subj.getTotals();
    const t = tt.coverage;

    // console.log('\n======= Parts:');
    // parts.forEach((v) => console.log(stringifyArgs(v)));
    // console.log('======= Total:');
    // console.log(stringifyArgs(t));
    // console.log('======= Before:');
    // console.log(totalPremium.toString(), totalPremiumRate.toString(), totalPremiumAt);

    if (parts.length > 0) {
      const z = BigNumber.from(0);
      expect(t.pendingCovered).eq(parts.reduce((p, v) => p.add(v.pendingCovered), z));
      expect(t.totalCovered).eq(parts.reduce((p, v) => p.add(v.totalCovered), z));
      expect(t.totalDemand).eq(parts.reduce((p, v) => p.add(v.totalDemand), z));
      expect(t.premiumRate).eq(parts.reduce((p, v) => p.add(v.premiumRate), z));
      expect(t.totalPremium).eq(parts.reduce((p, v) => p.add(v.totalPremium), z));
    }

    const at = await currentTime();
    if (totalPremiumAt != 0) {
      expect(t.premiumUpdatedAt).gte(totalPremiumAt);
      totalPremium = totalPremium.add(totalPremiumRate.mul(t.premiumUpdatedAt - totalPremiumAt));
    }

    expect(t.premiumUpdatedAt).lte(at);
    const expected = totalPremium.add(t.premiumRate.mul(at - t.premiumUpdatedAt));

    totalPremiumAt = t.premiumUpdatedAt;
    totalPremiumRate = t.premiumRate;
    // console.log('======= After:');
    // console.log(totalPremium.toString(), totalPremiumRate.toString(), totalPremiumAt, expected.toString());
    expect(t.totalPremium).eq(expected);
  };

  it('Add demand', async () => {
    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(0);
    }
    await subj.addCoverageDemand(insured1, 1000, RATE, false);
    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(2);
      expect(t.total.openRounds).eq(1000);
      expect(t.total.usableRounds).eq(0);
      expect(t.total.totalCoverable).eq(0);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(0);
      expect(t.coverage.totalDemand).eq(1000 * unitSize);
      expect(t.coverage.totalPremium).eq(0);
    }

    await subj.addCoverageDemand(insured2, 100, RATE, false);
    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(3);
      expect(t.total.openRounds).eq(1000);
      expect(t.total.usableRounds).eq(100);
      expect(t.total.totalCoverable).eq(2 * 100 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(0);
      expect(t.coverage.totalDemand).eq(1100 * unitSize);
      expect(t.coverage.totalPremium).eq(0);
    }

    await subj.addCoverageDemand(insured3, 2000, RATE, false);
    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(4);
      expect(t.total.openRounds).eq(1900);
      expect(t.total.usableRounds).eq(1000);
      expect(t.total.totalCoverable).eq(2100 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(0);
      expect(t.coverage.totalDemand).eq(3100 * unitSize);
      expect(t.coverage.totalPremium).eq(0);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 0, 0),
      await expectCoverage(insured2, 100, 0, 0),
      await expectCoverage(insured3, 2000, 0, 0)
    );
  });

  it('Add small coverage', async () => {
    await subj.addCoverage(30 * unitSize);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(4);
      expect(t.total.openRounds).eq(1900);
      expect(t.total.usableRounds).eq(990);
      expect(t.total.totalCoverable).eq(2070 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(30 * unitSize);
      expect(t.coverage.totalDemand).eq(3100 * unitSize);
      //      expect(t.coverage.totalPremium).eq(0);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 10, 0),
      await expectCoverage(insured2, 100, 10, 0),
      await expectCoverage(insured3, 2000, 10, 0)
    );
  });

  it('Add partial coverage', async () => {
    const roundSize = 3 * unitSize;
    const halfRoundSize = roundSize / 2;
    await subj.addCoverage(halfRoundSize, overrides);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(4);
      expect(t.total.openRounds).eq(1900);
      expect(t.total.usableRounds).eq(990);
      expect(t.total.totalCoverable).eq(2070 * unitSize - halfRoundSize);
      expect(t.coverage.pendingCovered).eq(halfRoundSize);
      expect(t.coverage.totalCovered).eq(30 * unitSize);
      expect(t.coverage.totalDemand).eq(3100 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 10, halfRoundSize / 3),
      await expectCoverage(insured2, 100, 10, halfRoundSize / 3),
      await expectCoverage(insured3, 2000, 10, halfRoundSize / 3)
    );

    {
      await increaseTime(5);

      await checkTotals(
        await expectCoverage(insured1, 1000, 10, halfRoundSize / 3),
        await expectCoverage(insured2, 100, 10, halfRoundSize / 3),
        await expectCoverage(insured3, 2000, 10, halfRoundSize / 3)
      );
    }

    await subj.addCoverage(roundSize / 2);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(4);
      expect(t.total.openRounds).eq(1900);
      expect(t.total.usableRounds).eq(989);
      expect(t.total.totalCoverable).eq(2067 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(33 * unitSize);
      expect(t.coverage.totalDemand).eq(3100 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 11, 0),
      await expectCoverage(insured2, 100, 11, 0),
      await expectCoverage(insured3, 2000, 11, 0)
    );
  });

  it('Add more coverage', async () => {
    await subj.addCoverage((100 - 11) * 3 * unitSize, overrides);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(3);
      expect(t.total.openRounds).eq(1900);
      expect(t.total.usableRounds).eq(900);
      expect(t.total.totalCoverable).eq(1800 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(300 * unitSize);
      expect(t.coverage.totalDemand).eq(3100 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 100, 0),
      await expectCoverage(insured2, 100, 100, 0),
      await expectCoverage(insured3, 2000, 100, 0)
    );
  });

  it('Add coverage when one insured is full', async () => {
    await subj.addCoverage(300 * unitSize, overrides);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(3);
      expect(t.total.openRounds).eq(1750);
      expect(t.total.usableRounds).eq(750);
      expect(t.total.totalCoverable).eq(1500 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(600 * unitSize);
      expect(t.coverage.totalDemand).eq(3100 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 250, 0),
      await expectCoverage(insured2, 100, 100, 0),
      await expectCoverage(insured3, 2000, 250, 0)
    );
  });

  it('Check rates over time (1)', async () => {
    await increaseTime(5);

    await checkTotals(
      await expectCoverage(insured1, 1000, 250, 0),
      await expectCoverage(insured2, 100, 100, 0),
      await expectCoverage(insured3, 2000, 250, 0)
    );
  });

  it('Extend coverage demand by insured2 then add coverage', async () => {
    await subj.addCoverageDemand(insured2, 100, RATE, false);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(4);
      expect(t.total.openRounds).eq(1650);
      expect(t.total.usableRounds).eq(750);
      expect(t.total.totalCoverable).eq(1600 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(600 * unitSize);
      expect(t.coverage.totalDemand).eq(3200 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 250, 0),
      await expectCoverage(insured2, 200, 100, 0),
      await expectCoverage(insured3, 2000, 250, 0)
    );

    await subj.addCoverage(150 * unitSize);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(4);
      expect(t.total.openRounds).eq(1650);
      expect(t.total.usableRounds).eq(700);
      expect(t.total.totalCoverable).eq(1450 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(750 * unitSize);
      expect(t.coverage.totalDemand).eq(3200 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 300, 0),
      await expectCoverage(insured2, 200, 150, 0),
      await expectCoverage(insured3, 2000, 300, 0)
    );
  });

  it('Check rates over time (2)', async () => {
    await increaseTime(5);

    await checkTotals(
      await expectCoverage(insured1, 1000, 300, 0),
      await expectCoverage(insured2, 200, 150, 0),
      await expectCoverage(insured3, 2000, 300, 0)
    );
  });

  it('Add excessive coverage', async () => {
    expect(await subj.excessCoverage()).eq(0);

    await subj.addCoverage(10000 * unitSize);

    const excess = (10000 - (3200 - 1000 /* imbalanced portion */ - 750)) * unitSize;
    expect(await subj.excessCoverage()).eq(excess);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(2);
      expect(t.total.openRounds).eq(1000);
      expect(t.total.usableRounds).eq(0);
      expect(t.total.totalCoverable).eq(0);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(2200 * unitSize);
      expect(t.coverage.totalDemand).eq(3200 * unitSize);
    }

    await checkTotals(
      await expectCoverage(insured1, 1000, 1000, 0),
      await expectCoverage(insured2, 200, 200, 0),
      await expectCoverage(insured3, 2000, 1000, 0)
    );
  });

  it('Add more excessive coverage', async () => {
    const excess = await subj.excessCoverage();
    await subj.addCoverage(1000 * unitSize);
    expect(await subj.excessCoverage()).eq(excess.add(1000 * unitSize));

    await checkTotals(
      await expectCoverage(insured1, 1000, 1000, 0),
      await expectCoverage(insured2, 200, 200, 0),
      await expectCoverage(insured3, 2000, 1000, 0)
    );
  });

  it('Multiple insured', async () => {
    const excess = await subj.excessCoverage();

    await subj.setRoundLimits(1, 2, 100);
    for (let i = 10; i > 0; i--) {
      const insured = createRandomAddress();
      await subj.addInsured(insured);
      await subj.addCoverageDemand(insured, 100, RATE, false);
      await checkTotals();
    }

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(3);
      expect(t.total.openRounds).eq(1000);
      expect(t.total.usableRounds).eq(100);
      expect(t.total.totalCoverable).eq(1100 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(2200 * unitSize);
      expect(t.coverage.totalDemand).eq(4200 * unitSize);
    }

    await subj.addCoverage(110 * unitSize, { gasLimit: 80000 });
    expect(await subj.excessCoverage()).eq(excess);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(3);
      expect(t.total.openRounds).eq(990);
      expect(t.total.usableRounds).eq(90);
      expect(t.total.totalCoverable).eq(990 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(2310 * unitSize);
      expect(t.coverage.totalDemand).eq(4200 * unitSize);
    }

    await expectCoverage(insured1, 1000, 1000, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 1010, 0);
    await checkTotals();
  });

  it('Cover everything', async () => {
    const excess = await subj.excessCoverage();
    await subj.addCoverageDemand(insured1, 990, RATE, false);

    //    await dumpState();
    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(3);
      expect(t.total.openRounds).eq(990);
      expect(t.total.usableRounds).eq(990);
      expect(t.total.totalCoverable).eq(2880 * unitSize);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(2310 * unitSize);
      expect(t.coverage.totalDemand).eq(5190 * unitSize);
      expect(t.coverage.totalDemand).eq(
        t.coverage.totalCovered.add(t.total.totalCoverable).add(t.coverage.pendingCovered)
      );
    }

    await expectCoverage(insured1, 1990, 1000, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 1010, 0);
    await checkTotals();

    await subj.addCoverage(2880 * unitSize);
    expect(await subj.excessCoverage()).eq(excess);

    {
      const t = await subj.getTotals();
      expect(t.total.batchCount).eq(1);
      expect(t.total.openRounds).eq(0);
      expect(t.total.usableRounds).eq(0);
      expect(t.total.totalCoverable).eq(0);
      expect(t.coverage.pendingCovered).eq(0);
      expect(t.coverage.totalCovered).eq(5190 * unitSize);
      expect(t.coverage.totalDemand).eq(5190 * unitSize);
    }

    await expectCoverage(insured1, 1990, 1990, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 2000, 0);
    await checkTotals();

    await subj.addCoverage(unitSize);
    expect(await subj.excessCoverage()).eq(excess.add(unitSize));
  });

  it('Add demand after depletion', async () => {
    await subj.addCoverageDemand(insured1, 10, RATE, false);

    await expectCoverage(insured1, 2000, 1990, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 2000, 0);
    await checkTotals();
  });

  it('Receive demand with one call', async () => {
    expect(await subj.receivedCoverage()).eq(0);
    const info0 = await subj.receivableCoverageDemand(insured1);
    expect(info0.availableCoverage).eq(info0.coverage.totalCovered);

    await subj.receiveDemandedCoverage(insured1, 65535);

    expect(await subj.receivedCoverage()).eq(info0.availableCoverage);

    const info1 = await subj.receivableCoverageDemand(insured1);
    expect(info1.availableCoverage).eq(0);
    expect(info1.coverage.pendingCovered).eq(info0.coverage.pendingCovered);
    expect(info1.coverage.premiumRate).eq(info0.coverage.premiumRate);
    expect(info1.coverage.totalCovered).eq(info0.coverage.totalCovered);
    expect(info1.coverage.totalDemand).eq(info0.coverage.totalDemand);
    expect(info1.coverage.totalPremium).gt(info0.coverage.totalPremium);
  });

  it('Receive demand with multiple calls', async () => {
    const expected = await subj.receivedCoverage();

    const info0 = await subj.receivableCoverageDemand(insured3);
    const startedAt = await currentTime();
    expect(info0.availableCoverage).eq(info0.coverage.totalCovered);

    const count = 10;
    for (let i = count; i > 0; i--) {
      await subj.receiveDemandedCoverage(insured3, i > 1 ? 1 : 65535);
      const info1 = await subj.receivableCoverageDemand(insured3);

      expect(await subj.receivedCoverage()).eq(expected.add(info0.availableCoverage.sub(info1.availableCoverage)));
      expect(info1.coverage.pendingCovered).eq(info0.coverage.pendingCovered);
      expect(info1.coverage.premiumRate).eq(info0.coverage.premiumRate);
      expect(info1.coverage.totalCovered).eq(info0.coverage.totalCovered);
      expect(info1.coverage.totalDemand).eq(info0.coverage.totalDemand);

      const passed = (await currentTime()) - startedAt;
      expect(info1.coverage.totalPremium).eq(info0.coverage.totalPremium.add(info0.coverage.premiumRate.mul(passed)));
    }

    expect(await subj.receivedCoverage()).eq(expected.add(info0.availableCoverage));

    await subj.receiveDemandedCoverage(insured3, 65535, testEnv.underCoverage ? overrides : { gasLimit: 45000 }); // there should be nothing to update
  });
});
