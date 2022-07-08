import { BigNumber } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { Ifaces } from '../../helpers/contract-ifaces';
import { Factories } from '../../helpers/contract-types';
import { createUserWallet, mustWaitTx } from '../../helpers/runtime-utils';
import { IInsurerPool, MockCollateralCurrencyStub, MockInsuredPool, MockPerpetualPool } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Weighted Pool benchmark', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let pool: MockPerpetualPool;
  let poolIntf: IInsurerPool;
  let fund: MockCollateralCurrencyStub;
  let iteration = 0;
  const weights: number[] = [];
  const insureds: MockInsuredPool[] = [];

  before(async () => {
    fund = await Factories.MockCollateralCurrencyStub.deploy();
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, fund.address);
    const extension = await Factories.PerpetualPoolExtension.deploy(zeroAddress(), unitSize, fund.address);
    pool = await Factories.MockPerpetualPool.deploy(extension.address, joinExtension.address);
    poolIntf = Ifaces.IInsurerPool.attach(pool.address);

    await pool.setPoolParams({
      maxAdvanceUnits: 100_000_000,
      minAdvanceUnits: 1_000,
      riskWeightTarget: 1_000,
      minInsuredShare: 100,
      maxInsuredShare: 1_500,
      minUnitsPerRound: 10,
      maxUnitsPerRound: 20,
      overUnitsPerRound: 30,
      maxDrawdownInverse: 10000,
    });
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

  const deployProtocolPools = async () => {
    const minUnits = 10;
    const riskWeight = 1000; // 10%

    const joinPool = async (poolDemand: number, riskWeightValue: number) => {
      const insured = await Factories.MockInsuredPool.deploy(
        fund.address,
        BigNumber.from(unitSize).mul(poolDemand),
        RATE,
        minUnits * unitSize
      );
      await pool.approveNextJoin(riskWeightValue);
      const tx = await mustWaitTx(insured.joinPool(pool.address));
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await poolIntf.receivableDemandedCoverage(insured.address, 0);
      insureds.push(insured);
      weights.push(riskWeightValue);
      console.log(
        `${iteration}\tDemand\t${insured.address}\t${stats.coverage.totalDemand.toString()}\t${tx.gasUsed.toString()}`
      );
      return stats.coverage;
    };

    for (const poolDemand of [10_000, 100_000, 1_000_000]) {
      await joinPool(poolDemand, riskWeight);
      await joinPool(poolDemand, riskWeight);
      await joinPool(poolDemand, riskWeight);
    }

    await joinPool(100000, riskWeight / 8);
  };

  it('Create 10 insured pools', async () => {
    iteration += 1;
    await deployProtocolPools();
  });

  const investByUser = async () => {
    const user = createUserWallet();
    await testEnv.deployer.sendTransaction({
      to: user.address,
      value: '0x16345785D8A0000',
    });

    const invest = async (kind: string, investment: number, excess?: BigNumber) => {
      const v = BigNumber.from(unitSize).mul(investment);
      const tx = await mustWaitTx(fund.connect(user).invest(pool.address, v));
      const extra = excess === undefined ? '' : `\t${excess.toString()}`;
      console.log(`${iteration}\tInvest\t${user.address}\t${v.toString()}\t${tx.gasUsed.toString()}\t${kind}${extra}`);
    };

    const smallInvestment = 10;
    const largeInvestment = 10000;
    await invest('init', smallInvestment);
    await invest('next', smallInvestment);
    await invest('next', largeInvestment);
    await invest('next', smallInvestment, await pool.getExcessCoverage());
  };

  it('Invest by 5 users', async () => {
    for (let i = 5; i > 0; i--) {
      await investByUser();
    }
  });

  const reconcilePools = async () => {
    for (const insured of insureds) {
      const tx = await mustWaitTx(insured.reconcileWithAllInsurers());
      const coverage = await insured.receivableByReconcileWithAllInsurers();
      console.log(
        `${iteration}\tReconcile\t${insured.address}\t${coverage.providedCoverage.toString()}\t${tx.gasUsed.toString()}`
      );
    }
  };

  it('Reconcile pools', reconcilePools);

  it('Create 10 insured pools (20 total)', async () => {
    iteration += 1;
    await deployProtocolPools();
  });

  it('Invest by 5 users', async () => {
    for (let i = 5; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);

  it('Create 30 insured pools (50 total)', async () => {
    iteration += 1;
    for (let i = 3; i > 0; i--) {
      await deployProtocolPools();
    }
  });

  it('Invest by 5 users', async () => {
    for (let i = 5; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);

  it('Invest by 35 users', async () => {
    iteration += 1;
    for (let i = 35; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);

  it('Create 50 insured pools (100 total)', async () => {
    iteration += 1;
    for (let i = 5; i > 0; i--) {
      await deployProtocolPools();
    }
  });

  it('Invest by 50 users', async () => {
    for (let i = 50; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);

  it('Create 100 insured pools (200 total)', async () => {
    iteration += 1;
    for (let i = 10; i > 0; i--) {
      await deployProtocolPools();
    }
  });

  it('Invest by 100 users', async () => {
    for (let i = 100; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);

  it('Create 300 insured pools (500 total)', async () => {
    iteration += 1;
    for (let i = 30; i > 0; i--) {
      await deployProtocolPools();
    }
  });

  it('Invest by 300 users', async () => {
    for (let i = 300; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);
});
