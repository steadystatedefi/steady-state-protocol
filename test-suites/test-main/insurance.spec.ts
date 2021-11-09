import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { MockCollateralFund, MockInsuredPool, MockWeightedPool } from '../../types';
import { expect } from 'chai';

makeSharedStateSuite('Weighted Rounds', (testEnv: TestEnv) => {
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const ratePerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let pool: MockWeightedPool;
  let fund: MockCollateralFund;
  let insured1: MockInsuredPool;

  before(async () => {
    fund = await Factories.MockCollateralFund.deploy();
    pool = await Factories.MockWeightedPool.deploy(fund.address, unitSize);
    insured1 = await Factories.MockInsuredPool.deploy(fund.address);
  });

  enum ProfileStatus {
    Unknown,
    Investor,
    InsuredUnknown,
    InsuredRejected,
    InsuredDeclined,
    InsuredJoining,
    InsuredAccepted,
    InsuredBanned,
  }

  it('Join weighted pool', async () => {
    await pool.requestJoin(insured1.address);
    expect(await pool.statusOf(insured1.address)).eq(ProfileStatus.InsuredAccepted);
  });
});
