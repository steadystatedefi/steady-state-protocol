import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { MockCollateralFund, MockInsuredPool, MockWeightedPool } from '../../types';
import { expect } from 'chai';

makeSharedStateSuite('Pool joins', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const ratePerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 10000 * unitSize;
  let pool: MockWeightedPool;
  let fund: MockCollateralFund;
  let insureds: MockInsuredPool[] = [];

  before(async () => {
    fund = await Factories.MockCollateralFund.deploy();
    pool = await Factories.MockWeightedPool.deploy(fund.address, unitSize);

    const minUnits = 10;
    const riskWeight = 1000; // 10%
    insureds.push(await Factories.MockInsuredPool.deploy(fund.address, poolDemand, ratePerUnit, minUnits, riskWeight));
    insureds.push(await Factories.MockInsuredPool.deploy(fund.address, poolDemand, ratePerUnit, minUnits, 10));
    insureds.push(await Factories.MockInsuredPool.deploy(fund.address, poolDemand, ratePerUnit, minUnits, riskWeight));
    insureds.push(await Factories.MockInsuredPool.deploy(fund.address, poolDemand, ratePerUnit, minUnits, riskWeight));
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
  }

  it('Join weighted pool', async () => {
    for (const insured of insureds) {
      await insured.joinPool(pool.address);
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
    }
  });
});
