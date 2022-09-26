import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { MemberStatus } from '../../helpers/access-flags';
import { HALF_RAY, RAY } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { advanceBlock, currentTime } from '../../helpers/runtime-utils';
import { MockCollateralCurrency, MockImperpetualPool } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Imperpetual Index Pool (2)', (testEnv: TestEnv) => {
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let pool: MockImperpetualPool;
  let cc: MockCollateralCurrency;

  before(async () => {
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockImperpetualPool.deploy(extension.address, joinExtension.address);
    await cc.registerInsurer(pool.address);
  });

  it('Reconcile an empty insured', async () => {
    const minUnits = 10;
    const riskWeight = 1000; // 10%
    const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
    const poolDemand = 0;

    const joinPool = async (riskWeightValue: number) => {
      const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
      const insured = await Factories.MockInsuredPool.deploy(
        cc.address,
        poolDemand,
        RATE,
        minUnits * unitSize,
        premiumToken.address
      );
      await pool.approveNextJoin(riskWeightValue, premiumToken.address);
      await insured.joinPool(pool.address, { gasLimit: 1000000 });
      expect(await pool.statusOf(insured.address)).eq(MemberStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      return insured;
    };

    const fund = await Factories.MockPremiumFund.deploy(cc.address);
    await pool.setPremiumDistributor(fund.address);
    await fund.registerPremiumActuary(pool.address, true);

    const insured = await joinPool(riskWeight);
    await insured.reconcileWithInsurers(0, 0);
  });

  it('Add coverage by users into an empty pool', async () => {
    let totalCoverageProvidedUnits = 0;
    let totalInvested = 0;

    expect(await cc.balanceOf(pool.address)).eq(0);

    let perUser = 400;
    for (const testUser of testEnv.users) {
      perUser += 100;
      totalCoverageProvidedUnits += perUser;

      const investment = unitSize * perUser;
      totalInvested += investment;
      await cc.mintAndTransfer(testUser.address, pool.address, investment, 0, {
        gasLimit: testEnv.underCoverage ? 2000000 : undefined,
      });

      expect(await cc.balanceOf(pool.address)).eq(totalInvested);

      const balance = await pool.balanceOf(testUser.address);
      expect(
        balance
          .mul(await pool.exchangeRate())
          .add(HALF_RAY)
          .div(RAY)
      ).eq(unitSize * perUser);
    }

    {
      let total = await pool.totalSupply();
      for (const testUser of testEnv.users) {
        const balance = await pool.balanceOf(testUser.address);
        total = total.sub(balance);
      }
      expect(total).eq(0);
    }

    if (testEnv.underCoverage) {
      return;
    }

    const totals = await pool.getTotals();
    expect(totals.coverage.totalDemand).eq(0);
    expect(totals.coverage.premiumRate).eq(0);

    expect(totals.coverage.totalCovered.add(totals.coverage.pendingCovered)).eq(0);
    const excess = await pool.getExcessCoverage();
    expect(excess).eq(totalCoverageProvidedUnits * unitSize);

    expect(await pool.totalSupplyValue()).eq(
      totals.coverage.totalCovered.add(totals.coverage.pendingCovered).add(totals.coverage.totalPremium).add(excess)
    );
  });

  it('Transfer imperpetual pool balance', async () => {
    const [user1, user2] = testEnv.users;
    const amount = 100 * unitSize;

    await cc.mintAndTransfer(user1.address, pool.address, amount, 0);
    await pool.connect(user1).transfer(user2.address, amount);
    expect(await pool.balanceOf(user2.address)).eq(amount);
  });

  it('Transfer insured rate balance', async () => {
    const user = testEnv.users[1];
    await pool.setMaxInsuredSharePct(1_00_00);

    const minUnits = 10;
    const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
    const poolDemand = 100000 * unitSize;

    const joinPool = async (riskWeightValue: number) => {
      const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
      const insured = await Factories.MockInsuredPool.deploy(
        cc.address,
        poolDemand,
        RATE,
        minUnits * unitSize,
        premiumToken.address
      );
      await pool.approveNextJoin(riskWeightValue, premiumToken.address);
      await insured.joinPool(pool.address, { gasLimit: 1000000 });
      expect(await pool.statusOf(insured.address)).eq(MemberStatus.Accepted);

      return insured;
    };

    const insured = await joinPool(1_00_00);
    const t1 = await currentTime();
    let bals = await insured.balancesOf(pool.address);
    const rate = bals.rate;

    await advanceBlock((await currentTime()) + 15);
    let t2 = (await pool.transferInsuredPoolToken(insured.address, user.address, rate)).timestamp;
    t2 = t2 === undefined ? await currentTime() : t2;

    bals = await insured.balancesOf(pool.address);
    expect(bals.rate).eq(0);
    expect(bals.premium).eq(rate.mul(t2 - t1));
    bals = await insured.balancesOf(user.address);
    expect(bals.rate).eq(rate);
    expect(bals.premium).eq(0);
    expect(await insured.balanceOf(user.address)).eq(rate);
  });
});
