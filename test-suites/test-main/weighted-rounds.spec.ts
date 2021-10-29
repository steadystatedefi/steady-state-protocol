import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { RAY } from '../../helpers/constants';
import { createRandomAddress } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { MockWeightedRounds } from '../../types';
import { tEthereumAddress } from '../../helpers/types';
import { expect } from 'chai';
import { stringifyArgs } from '../../helpers/etherscan-verification';

makeSharedStateSuite('Weighted Rounds', (testEnv: TestEnv) => {
  const unitSize = 1000;
  let subj: MockWeightedRounds;
  let insured1: tEthereumAddress;
  let insured2: tEthereumAddress;
  let insured3: tEthereumAddress;

  before(async () => {
    subj = await Factories.MockWeightedRounds.deploy(unitSize);
    await subj.setRoundLimits(1, 2, 3);
    insured1 = createRandomAddress();
    insured2 = createRandomAddress();
    insured3 = createRandomAddress();
  });

  const expectCoverage = async (insured: tEthereumAddress, demand: number, covered: number, pending: number) => {
    const tt = await subj.getCoverageDemand(insured);
    const t = tt.coverage;
    expect(t.pendingCovered).eq(pending);
    expect(t.totalCovered).eq(covered * unitSize);
    expect(t.totalDemand).eq(demand * unitSize);
  };

  it('Add demand', async () => {
    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(0);
    }
    await subj.addCoverageDemand(insured1, 1000, RAY, false);
    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(1);
      expect(t.openRounds).eq(1000);
      expect(t.usableRounds).eq(0);
      expect(t.totalUsableDemand).eq(0);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(0);
      expect(t.demanded.totalDemand).eq(1000 * unitSize);
    }

    await subj.addCoverageDemand(insured2, 100, RAY, false);
    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(2);
      expect(t.openRounds).eq(1000);
      expect(t.usableRounds).eq(100);
      expect(t.totalUsableDemand).eq(2 * 100 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(0);
      expect(t.demanded.totalDemand).eq(1100 * unitSize);
    }

    await subj.addCoverageDemand(insured3, 2000, RAY, false);
    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(3);
      expect(t.openRounds).eq(1900);
      expect(t.usableRounds).eq(1000);
      expect(t.totalUsableDemand).eq(2100 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(0);
      expect(t.demanded.totalDemand).eq(3100 * unitSize);
    }

    await expectCoverage(insured1, 1000, 0, 0);
    await expectCoverage(insured2, 100, 0, 0);
    await expectCoverage(insured3, 2000, 0, 0);
  });

  it('Add small coverage', async () => {
    await subj.addCoverage(30 * unitSize);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(3);
      expect(t.openRounds).eq(1900);
      expect(t.usableRounds).eq(990);
      expect(t.totalUsableDemand).eq(2070 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(30 * unitSize);
      expect(t.demanded.totalDemand).eq(3100 * unitSize);
    }

    await expectCoverage(insured1, 1000, 10, 0);
    await expectCoverage(insured2, 100, 10, 0);
    await expectCoverage(insured3, 2000, 10, 0);
  });

  it('Add partial coverage', async () => {
    const roundSize = 3 * unitSize;
    const halfRoundSize = roundSize / 2;
    await subj.addCoverage(halfRoundSize);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(3);
      expect(t.openRounds).eq(1900);
      expect(t.usableRounds).eq(990);
      expect(t.totalUsableDemand).eq(2070 * unitSize - halfRoundSize);
      expect(t.demanded.pendingCovered).eq(halfRoundSize);
      expect(t.demanded.totalCovered).eq(30 * unitSize);
      expect(t.demanded.totalDemand).eq(3100 * unitSize);
    }

    await expectCoverage(insured1, 1000, 10, halfRoundSize / 3);
    await expectCoverage(insured2, 100, 10, halfRoundSize / 3);
    await expectCoverage(insured3, 2000, 10, halfRoundSize / 3);

    await subj.addCoverage(roundSize / 2);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(3);
      expect(t.openRounds).eq(1900);
      expect(t.usableRounds).eq(989);
      expect(t.totalUsableDemand).eq(2067 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(33 * unitSize);
      expect(t.demanded.totalDemand).eq(3100 * unitSize);
    }

    await expectCoverage(insured1, 1000, 11, 0);
    await expectCoverage(insured2, 100, 11, 0);
    await expectCoverage(insured3, 2000, 11, 0);
  });

  it('Add more coverage', async () => {
    await subj.addCoverage((100 - 11) * 3 * unitSize);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(2);
      expect(t.openRounds).eq(1900);
      expect(t.usableRounds).eq(900);
      expect(t.totalUsableDemand).eq(1800 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(300 * unitSize);
      expect(t.demanded.totalDemand).eq(3100 * unitSize);
    }

    await expectCoverage(insured1, 1000, 100, 0);
    await expectCoverage(insured2, 100, 100, 0);
    await expectCoverage(insured3, 2000, 100, 0);
  });

  it('Add coverage when one insured is full', async () => {
    await subj.addCoverage(300 * unitSize);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(2);
      expect(t.openRounds).eq(1750);
      expect(t.usableRounds).eq(750);
      expect(t.totalUsableDemand).eq(1500 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(600 * unitSize);
      expect(t.demanded.totalDemand).eq(3100 * unitSize);
    }

    await expectCoverage(insured1, 1000, 250, 0);
    await expectCoverage(insured2, 100, 100, 0);
    await expectCoverage(insured3, 2000, 250, 0);
  });

  it('Extend coverage demand by insured2 then add coverage', async () => {
    await subj.addCoverageDemand(insured2, 100, RAY, false);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(4);
      expect(t.openRounds).eq(1650);
      expect(t.usableRounds).eq(750);
      expect(t.totalUsableDemand).eq(1600 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(600 * unitSize);
      expect(t.demanded.totalDemand).eq(3200 * unitSize);
    }

    await expectCoverage(insured1, 1000, 250, 0);
    await expectCoverage(insured2, 200, 100, 0);
    await expectCoverage(insured3, 2000, 250, 0);

    await subj.addCoverage(150 * unitSize);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(3);
      expect(t.openRounds).eq(1650);
      expect(t.usableRounds).eq(700);
      expect(t.totalUsableDemand).eq(1450 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(750 * unitSize);
      expect(t.demanded.totalDemand).eq(3200 * unitSize);
    }

    await expectCoverage(insured1, 1000, 300, 0);
    await expectCoverage(insured2, 200, 150, 0);
    await expectCoverage(insured3, 2000, 300, 0);
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

  it('Add excessive coverage', async () => {
    expect(await subj.excessCoverage()).eq(0);

    await subj.addCoverage(10000 * unitSize);

    const excess = (10000 - (3200 - 1000 /* imbalanced portion */ - 750)) * unitSize;
    expect(await subj.excessCoverage()).eq(excess);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(1);
      expect(t.openRounds).eq(1000);
      expect(t.usableRounds).eq(0);
      expect(t.totalUsableDemand).eq(0);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(2200 * unitSize);
      expect(t.demanded.totalDemand).eq(3200 * unitSize);
    }

    await expectCoverage(insured1, 1000, 1000, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 1000, 0);
  });

  it('Add more excessive coverage', async () => {
    const excess = await subj.excessCoverage();
    await subj.addCoverage(1000 * unitSize);
    expect(await subj.excessCoverage()).eq(excess.add(1000 * unitSize));
  });

  it('Multiple insured', async () => {
    const excess = await subj.excessCoverage();

    await subj.setRoundLimits(1, 2, 100);
    for (let i = 10; i > 0; i--) {
      const insured = createRandomAddress();
      await subj.addCoverageDemand(insured, 100, RAY, false);
    }

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(2);
      expect(t.openRounds).eq(1000);
      expect(t.usableRounds).eq(100);
      expect(t.totalUsableDemand).eq(1100 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(2200 * unitSize);
      expect(t.demanded.totalDemand).eq(4200 * unitSize);
    }

    await subj.addCoverage(110 * unitSize, { gasLimit: 80000 });
    expect(await subj.excessCoverage()).eq(excess);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(2);
      expect(t.openRounds).eq(990);
      expect(t.usableRounds).eq(90);
      expect(t.totalUsableDemand).eq(990 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(2310 * unitSize);
      expect(t.demanded.totalDemand).eq(4200 * unitSize);
    }

    await expectCoverage(insured1, 1000, 1000, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 1010, 0);
  });

  it('Cover everything', async () => {
    const excess = await subj.excessCoverage();
    await subj.addCoverageDemand(insured1, 990, RAY, false);

    //    await dumpState();
    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(3);
      expect(t.openRounds).eq(990);
      expect(t.usableRounds).eq(990);
      expect(t.totalUsableDemand).eq(2880 * unitSize);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(2310 * unitSize);
      expect(t.demanded.totalDemand).eq(5190 * unitSize);
      expect(t.demanded.totalDemand).eq(
        t.demanded.totalCovered.add(t.totalUsableDemand).add(t.demanded.pendingCovered)
      );
    }

    await expectCoverage(insured1, 1990, 1000, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 1010, 0);

    await subj.addCoverage(2880 * unitSize);
    expect(await subj.excessCoverage()).eq(excess);

    {
      const t = await subj.getTotals();
      expect(t.batchCount).eq(1);
      expect(t.openRounds).eq(0);
      expect(t.usableRounds).eq(0);
      expect(t.totalUsableDemand).eq(0);
      expect(t.demanded.pendingCovered).eq(0);
      expect(t.demanded.totalCovered).eq(5190 * unitSize);
      expect(t.demanded.totalDemand).eq(5190 * unitSize);
    }

    await expectCoverage(insured1, 1990, 1990, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 2000, 0);

    await subj.addCoverage(unitSize);
    expect(await subj.excessCoverage()).eq(excess.add(unitSize));
  });

  it('Add demand after depletion', async () => {
    await subj.addCoverageDemand(insured1, 10, RAY, false);

    await expectCoverage(insured1, 2000, 1990, 0);
    await expectCoverage(insured2, 200, 200, 0);
    await expectCoverage(insured3, 2000, 2000, 0);
  });
});
