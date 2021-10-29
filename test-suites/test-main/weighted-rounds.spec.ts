import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { RAY } from '../../helpers/constants';
import { createRandomAddress } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { MockWeightedRounds } from '../../types';
import { tEthereumAddress } from '../../helpers/types';
import { expect } from 'chai';

makeSharedStateSuite('Weighted Rounds', (testEnv: TestEnv) => {
  const unitSize = 1000;
  let subj: MockWeightedRounds;
  let insured1: tEthereumAddress;
  let insured2: tEthereumAddress;
  let insured3: tEthereumAddress;

  before(async () => {
    subj = await Factories.MockWeightedRounds.deploy(unitSize);
    subj.setRoundLimits(1, 2, 3);
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
});
