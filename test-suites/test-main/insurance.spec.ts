import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { RAY } from '../../helpers/constants';
import { MockCollateralFund, MockInsuredPool, MockWeightedPool, PremiumCollector } from '../../types';
import { expect } from 'chai';
import { createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { tEthereumAddress } from '../../helpers/types';
import { Wallet } from '@ethersproject/wallet';

makeSharedStateSuite('Pool joins', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 10000 * unitSize;
  let payInToken: tEthereumAddress;
  const protocol = Wallet.createRandom();
  let pool: MockWeightedPool;
  let fund: MockCollateralFund;
  let collector: PremiumCollector;
  let insureds: MockInsuredPool[] = [];
  let insuredUnits: number[] = [];
  let insuredTS: number[] = [];

  before(async () => {
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    fund = await Factories.MockCollateralFund.deploy();
    pool = await Factories.MockWeightedPool.deploy(fund.address, unitSize, decimals, extension.address);
    collector = await Factories.PremiumCollector.deploy();

    payInToken = createRandomAddress();
    await collector.setPremiumScale(payInToken, [fund.address], [RAY]);
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
        fund.address,
        poolDemand,
        RATE,
        minUnits,
        riskWeight,
        decimals
      );
      insuredTS.push(await currentTime());
      await insured.joinPool(pool.address);
      expect(await pool.statusOf(insured.address)).eq(InsuredStatus.Accepted);
      const { 0: generic, 1: chartered } = await insured.getInsurers();
      expect(generic).eql([]);
      expect(chartered).eql([pool.address]);

      const stats = await pool.receivableDemandedCoverage(insured.address);
      insureds.push(insured);
      collector.registerProtocolTokens(protocol.address, [insured.address], [payInToken]);
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

  let totalCoverageProvidedUnits = 0;

  it('Add coverage by users', async () => {
    const timestamps: number[] = [];
    const userUnits: number[] = [];

    let totalPremium = 0;
    let totalPremiumRate = 0;

    let _perUser = 4;
    for (const user of testEnv.users) {
      timestamps.push(await currentTime());
      _perUser++;
      totalCoverageProvidedUnits += _perUser;
      userUnits.push(_perUser);
      await fund
        .connect(user)
        .invest(pool.address, unitSize * _perUser, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });
      const interest = await pool.interestRate(user.address);
      expect(interest.accumulated).eq(0);
      expect(interest.rate).eq(premiumPerUnit * _perUser);

      const balance = await pool.balanceOf(user.address);
      expect(balance).eq(unitSize * _perUser);
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

  it('Check coverage per insured', async () => {
    let totalInsuredPremiumRate = 0;
    let totalInsuredPremium = 0;

    const totals = await pool.getTotals();
    const totalDemandUnits = totals.coverage.totalDemand.div(unitSize).toNumber();

    for (let index = 0; index < insureds.length; index++) {
      const insured = insureds[index];
      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
      expect(coverage.totalDemand).eq(insuredUnits[index] * unitSize);

      const covered = coverage.totalCovered.add(coverage.pendingCovered);
      expect(coverage.premiumRate).eq(
        covered
          .mul(premiumPerUnit)
          .add(unitSize - 1)
          .div(unitSize)
      );
      expect(covered.toNumber()).approximately(
        (totalCoverageProvidedUnits * unitSize * insuredUnits[index]) / totalDemandUnits,
        1
      );

      {
        const balances = await insured.balancesOf(pool.address);

        // here demanded coverage is in use - so a protocol is charged at max
        expect(balances.available).eq(coverage.totalDemand.mul(premiumPerUnit).div(unitSize));
        expect(balances.holded).eq(0);

        // NB! premium is charged for _demand_ added to guarantee sufficient flow of premium.
        // Using reconcillation will match it with actual coverage.
        if (!testEnv.underCoverage) {
          expect(balances.premium).eq(balances.available.mul((await currentTime()) - insuredTS[index] - 1));
        }

        if (coverage.totalPremium.eq(0)) {
          expect(balances.premium).eq(0);
        } else {
          expect(balances.premium).gt(coverage.totalPremium);
        }

        expect(balances.available).eq(await insured.totalSupply());

        const totalPremium = await insured.totalPremium();
        expect(balances.available).eq(totalPremium.rate);
        expect(balances.premium).eq(totalPremium.accumulated);

        totalInsuredPremium += totalPremium.accumulated.toNumber();
        totalInsuredPremiumRate += totalPremium.rate.toNumber();
      }
    }
    expect(totalInsuredPremiumRate).eq(totalDemandUnits * premiumPerUnit);
    if (totalInsuredPremium == 0) {
      expect(0).gt(totals.coverage.premiumRate);
      expect(0).gt(totals.coverage.totalPremium);
    } else {
      expect(totalInsuredPremiumRate).gt(totals.coverage.premiumRate);
      expect(totalInsuredPremium).gt(totals.coverage.totalPremium);
    }

    const payList = await collector.expectedPayAfter(protocol.address, 1);
    expect(payList.length).eq(1);
    expect(payList[0].token).eq(payInToken);
    expect(totalInsuredPremiumRate).eq(payList[0].amount);
  });

  it('Reconcile', async () => {
    for (const insured of insureds) {
      await insured.reconcileWithAllInsurers();
      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
      // console.log('after', insured.address, coverage.totalPremium.toNumber(), coverage.premiumRate.toNumber());

      {
        const balances = await insured.balancesOf(pool.address);

        // here demanded coverage is in use - so a protocol is charged at max
        expect(balances.available).eq(coverage.totalDemand.mul(premiumPerUnit).div(unitSize));
        expect(balances.holded).eq(0);

        // NB! reconcillation match it with actual coverage.
        expect(balances.premium).eq(coverage.totalPremium);
        expect(balances.available).eq(await insured.totalSupply());
        if (coverage.premiumRate.eq(0)) {
          expect(balances.available).eq(0);
        } else {
          expect(balances.available).gt(coverage.premiumRate);
        }

        const totalPremium = await insured.totalPremium();
        expect(balances.available).eq(totalPremium.rate);
        expect(balances.premium).eq(totalPremium.accumulated);
      }
    }

    let totalInsuredPremium = 0;
    let totalInsuredPremiumRate = 0;

    for (const insured of insureds) {
      const { coverage } = await pool.receivableDemandedCoverage(insured.address);
      totalInsuredPremium += coverage.totalPremium.toNumber();
      totalInsuredPremiumRate += coverage.premiumRate.toNumber();
    }

    const totals = await pool.getTotals();
    let n = totals.coverage.premiumRate.toNumber();
    expect(totalInsuredPremiumRate).within(n, n + insureds.length); // rounding up may give +1 per insured

    n = totals.coverage.totalPremium.toNumber();
    if (!testEnv.underCoverage) {
      expect(totalInsuredPremium).within(n, n + insureds.length * ((await currentTime()) - insuredTS[0] - 1));
    }
  });

  it('Excess Coverage', async () => {
    await fund
      .connect(testEnv.users[0])
      .invest(pool.address, unitSize * 10000, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });
    await insureds[0].increaseRequiredCoverage(unitSize * 10000);
    await insureds[0].pushCoverageDemandTo(pool.address, unitSize * 2000);
    await pool.pushCoverageExcess();
    console.log(await insureds[0].reconcileWithAllInsurers());
    //await pool.pushCoverageExcess();
  });
});
