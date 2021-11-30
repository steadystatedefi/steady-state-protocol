import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { RAY } from '../../helpers/constants';
import { MockCollateralFund, MockInsuredPool, MockWeightedPool, PremiumCollector } from '../../types';
import { expect } from 'chai';
import { createRandomAddress, createUserWallet, mustWaitTx } from '../../helpers/runtime-utils';
import { tEthereumAddress } from '../../helpers/types';
import { Wallet } from '@ethersproject/wallet';
import { BigNumber } from '@ethersproject/bignumber';

makeSharedStateSuite('Weighted Pool benchmark', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let payInToken: tEthereumAddress;
  let pool: MockWeightedPool;
  let fund: MockCollateralFund;
  let collector: PremiumCollector;
  let iteration = 0;
  const weights: number[] = [];
  const insureds: MockInsuredPool[] = [];

  before(async () => {
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    fund = await Factories.MockCollateralFund.deploy();
    pool = await Factories.MockWeightedPool.deploy(fund.address, unitSize, decimals, extension.address);
    collector = await Factories.PremiumCollector.deploy();

    payInToken = createRandomAddress();
    await collector.setPremiumScale(payInToken, [fund.address], [RAY]);

    await pool.setPoolParams({
      maxAdvanceUnits: 10000000,
      minAdvanceUnits: 1000,
      riskWeightTarget: 1000,
      minInsuredShare: 100,
      maxInsuredShare: 1500,
      minUnitsPerRound: 10,
      maxUnitsPerRound: 20,
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
    const protocol = Wallet.createRandom();

    const joinPool = async (poolDemand: number, riskWeight: number) => {
      const insured = await Factories.MockInsuredPool.deploy(
        fund.address,
        BigNumber.from(unitSize).mul(poolDemand),
        RATE,
        minUnits,
        riskWeight,
        decimals
      );
      await insured.joinPool(pool.address);
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await pool.receivableDemandedCoverage(insured.address);
      insureds.push(insured);
      weights.push(riskWeight);
      collector.registerProtocolTokens(protocol.address, [insured.address], [payInToken]);
      console.log(`${iteration}\tDemand\t${insured.address}\t${stats.coverage.totalDemand.toString()}`);
      return stats.coverage;
    };

    for (let poolDemand of [10000, 100000, 1000000]) {
      await joinPool(poolDemand, riskWeight);
      await joinPool(poolDemand, riskWeight);
      await joinPool(poolDemand, riskWeight);
    }
    await joinPool(100000, riskWeight / 8);
  };

  it('Create 10 insured pools', async () => {
    iteration++;
    await deployProtocolPools();
  });

  const investByUser = async () => {
    const user = createUserWallet();
    await testEnv.deployer.sendTransaction({
      to: user.address,
      value: '0x16345785D8A0000',
    });

    const invest = async (kind: string, investment: number) => {
      const tx = await mustWaitTx(fund.connect(user).invest(pool.address, BigNumber.from(unitSize).mul(investment)));
      console.log(`${iteration}\tInvest\t${kind}\t${user.address}\t${investment}\t${tx.gasUsed}`);
      // const totals = await pool.getTotals();
      // console.log(totals.coverage.totalCovered.add(totals.coverage.pendingCovered).toString());
    };

    const smallInvestment = 10;
    const largeInvestment = 10000;
    await invest('init', smallInvestment);
    await invest('next', smallInvestment);
    await invest('next', largeInvestment);
    await invest('next', smallInvestment);
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
        `${iteration}\tReconcile\t${insured.address}\t${coverage.providedCoverage.toString()}\t${tx.gasUsed}`
      );
    }
  };

  it('Reconcile pools', reconcilePools);

  it('Create 10 insured pools (20 total)', async () => {
    iteration++;
    await deployProtocolPools();
  });

  it('Invest by 5 users', async () => {
    for (let i = 5; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);

  it('Create 30 insured pools (50 total)', async () => {
    iteration++;
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

  it('Invest by 50 users', async () => {
    iteration++;
    for (let i = 50; i > 0; i--) {
      await investByUser();
    }
  });

  it('Reconcile pools', reconcilePools);
});
