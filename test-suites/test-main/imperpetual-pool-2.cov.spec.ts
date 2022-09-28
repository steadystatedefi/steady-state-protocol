import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish } from 'ethers';

import { MemberStatus } from '../../helpers/access-flags';
import { HALF_RAY, RAY, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { advanceBlock, currentTime } from '../../helpers/runtime-utils';
import { IInsurerPool, MockCollateralCurrency, MockERC20, MockImperpetualPool, MockInsuredPool } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Imperpetual Index Pool (2)', (testEnv: TestEnv) => {
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let pool: MockImperpetualPool;
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
  });

  const minUnits = 10;
  const riskWeight = 1000; // 10%
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a

  const joinPool = async (riskWeightValue: number, demand: BigNumberish, premiumToken: MockERC20) => {
    const insured = await Factories.MockInsuredPool.deploy(
      cc.address,
      demand,
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

  it('Reconcile an empty insured', async () => {
    const fund = await Factories.MockPremiumFund.deploy(cc.address);
    await pool.setPremiumDistributor(fund.address);
    await fund.registerPremiumActuary(pool.address, true);
    const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);

    const insured = await joinPool(riskWeight, 0, premiumToken);
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

  it.only('SyncAsset before reconcile', async () => {
    const demand = BigNumber.from(4000 * unitSize);
    const ratePerInsured = demand.mul(RATE).div(WAD);
    const insureds: MockInsuredPool[] = [];

    const fund = await Factories.MockPremiumFund.deploy(cc.address);
    await pool.setPremiumDistributor(fund.address);
    await fund.registerPremiumActuary(pool.address, true);
    const premiumToken1 = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
    const premiumToken2 = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
    fund.setPrice(premiumToken1.address, WAD);
    fund.setPrice(premiumToken2.address, WAD);

    insureds.push(await joinPool(riskWeight, demand, premiumToken1));
    insureds.push(await joinPool(riskWeight, demand, premiumToken2));
    insureds.push(await joinPool(riskWeight, demand, premiumToken2));
    await premiumToken1.mint(insureds[0].address, WAD);
    await premiumToken2.mint(insureds[1].address, WAD);
    await cc.mintAndTransfer(user.address, pool.address, demand.mul(3), 0);

    const t: number[] = [0, 0, 0];

    for (let i = 0; i < insureds.length; i++) {
      await insureds[i].reconcileWithInsurers(0, 0);
    }

    await advanceBlock((await currentTime()) + 200);
    await fund.syncAsset(pool.address, 0, premiumToken1.address);
    for (let i = 0; i < insureds.length; i++) {
      let tt = (await insureds[i].reconcileWithInsurers(0, 0)).timestamp;
      tt = tt === undefined ? await currentTime() : tt;
      t[i] = tt;
    }

    let b1 = (await fund.balancerBalanceOf(pool.address, premiumToken1.address)).accumAmount;
    let b2 = (await fund.balancerBalanceOf(pool.address, premiumToken2.address)).accumAmount;

    // Add 10s to compensate creating pool and other txs
    let b2compensated = b2.add(ratePerInsured.mul(t[1] - t[0] + 10));
    expect(b1).lte(b2compensated);

    await advanceBlock((await currentTime()) + 200);

    for (let i = 0; i < insureds.length; i++) {
      let tt = (await insureds[i].reconcileWithInsurers(0, 0)).timestamp;
      tt = tt === undefined ? await currentTime() : tt;
      t[i] = tt;
    }

    b1 = (await fund.balancerBalanceOf(pool.address, premiumToken1.address)).accumAmount;
    b2 = (await fund.balancerBalanceOf(pool.address, premiumToken2.address)).accumAmount;

    b2compensated = b2.add(ratePerInsured.mul(t[1] - t[0] + 20));
    expect(b1).lte(b2compensated);
  });
});
