import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { MAX_UINT, RAY, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { advanceBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import {
  IInsurerPool,
  MockCollateralCurrency,
  MockImperpetualPool,
  MockInsuredPool,
  MockPremiumFund,
} from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Minimum Drawdown (with Imperpetual Index Pool)', (testEnv: TestEnv) => {
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const drawdownPct = 10; // 10% constant inside MockImperpetualPool
  const rate = 1e12;
  const demandPerInsured = 4000 * unitSize;
  let demanded: BigNumber;

  let pool: MockImperpetualPool;
  let poolIntf: IInsurerPool;
  let cc: MockCollateralCurrency;
  let premFund: MockPremiumFund;
  let user: SignerWithAddress;

  const insureds: MockInsuredPool[] = [];

  const joinPool = async (riskWeightValue: number) => {
    const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
    const insured = await Factories.MockInsuredPool.deploy(
      cc.address,
      demandPerInsured,
      rate,
      10 * unitSize,
      premiumToken.address
    );
    await pool.approveNextJoin(riskWeightValue, premiumToken.address);
    await insured.joinPool(pool.address, { gasLimit: 1000000 });

    const stats = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    insureds.push(insured);
    return stats.coverage;
  };

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockImperpetualPool.deploy(extension.address, joinExtension.address);
    await cc.registerInsurer(pool.address);
    poolIntf = Factories.IInsurerPool.attach(pool.address);
    premFund = (await Factories.MockPremiumFund.deploy(cc.address)).connect(user);
    await premFund.registerPremiumActuary(pool.address, true);

    // enable drawdown with flat curve / zero fee
    await premFund.setAssetConfig(pool.address, cc.address, {
      spConst: 0,
      calc: BigNumber.from(1_00_00)
        .shl(144 + 64)
        .or(BigNumber.from(1).shl(14 + 32 + 64 + 144)), // calc.n = 100%; calc.flags = BF_EXTERNAL
    });

    demanded = BigNumber.from(0);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
  });

  const collectAvailableDrawdown = async (): Promise<BigNumber> => {
    const { availableDrawdownValue: drawdown } = await pool.callStatic.collectDrawdownPremium();
    return drawdown;
  };

  it('Drawdown User Premium', async () => {
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);

    let drawdown = await collectAvailableDrawdown();
    let balance = await pool.balanceOf(user.address);
    let ccbalance = await cc.balanceOf(user.address);

    const valueToAmount = async (v: BigNumber, timeDelta?: number): Promise<BigNumber> => {
      let exchangeRate: BigNumber;
      if (timeDelta) {
        const tb = await pool.totalSupply();
        const tv = await pool.totalSupplyValue();
        const { coverage } = await pool.getTotals();
        exchangeRate = tv.add(coverage.premiumRate.mul(timeDelta)).mul(RAY).div(tb);
      } else {
        exchangeRate = await pool.exchangeRate();
      }
      expect(exchangeRate).gte(RAY);
      return v.mul(RAY).add(v.div(2)).div(exchangeRate);
    };

    let amtSwap = BigNumber.from(10000);
    let tokenSwap = await valueToAmount(amtSwap);

    expect(drawdown).eq((await pool.getTotals()).coverage.totalCovered.mul(drawdownPct).div(100));

    await premFund.swapAsset(pool.address, user.address, user.address, amtSwap, cc.address, amtSwap);
    {
      expect(await collectAvailableDrawdown()).eq(drawdown.sub(amtSwap));
      expect(await pool.balanceOf(user.address)).lte(balance.sub(tokenSwap));
      expect(await cc.balanceOf(user.address)).eq(ccbalance.add(amtSwap));
    }

    drawdown = await collectAvailableDrawdown();

    balance = await pool.balanceOf(user.address);
    ccbalance = await cc.balanceOf(user.address);

    {
      const { coverage } = await pool.getTotals();
      expect(drawdown).closeTo(
        coverage.totalCovered.mul(drawdownPct).div(100),
        coverage.totalCovered.mul(5).div(1000) // 0.5% tolerance
      );
    }

    amtSwap = drawdown.add(1);
    // should NOT cause overflow / underflow
    expect(
      await premFund.callStatic.swapAsset(pool.address, user.address, user.address, amtSwap, cc.address, amtSwap)
    ).eq(0);

    amtSwap = drawdown;
    tokenSwap = await valueToAmount(amtSwap, 1);
    await premFund.swapAsset(pool.address, user.address, user.address, amtSwap, cc.address, 0);
    {
      expect(await collectAvailableDrawdown()).eq(0);
      if (!testEnv.underCoverage) {
        expect(tokenSwap).lte(balance.sub(await pool.balanceOf(user.address)));
      }
      expect(await cc.balanceOf(user.address)).eq(ccbalance.add(amtSwap));
    }

    balance = await pool.balanceOf(user.address);
    ccbalance = await cc.balanceOf(user.address);
    await premFund.swapAsset(pool.address, user.address, user.address, 1000, cc.address, 0);
    {
      expect(await pool.balanceOf(user.address)).eq(balance);
      expect(await cc.balanceOf(user.address)).eq(ccbalance);
    }

    const amtMinted = BigNumber.from(100).mul(unitSize);
    await cc.mintAndTransfer(user.address, pool.address, amtMinted, 0);
    expect(await collectAvailableDrawdown()).eq(amtMinted.mul(drawdownPct).div(100));
  });

  const checkForepay = async () => {
    const coverageForepayPct = (await pool.getPoolParams()).coverageForepayPct;

    for (let i = 0; i < insureds.length; i++) {
      const insured = insureds[i];
      await insured.reconcileWithInsurers(0, 0, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });
      const coverage = (await poolIntf.receivableDemandedCoverage(insured.address, 0)).coverage.totalCovered;
      expect(await cc.balanceOf(insured.address)).eq(coverage.mul(coverageForepayPct).div(10000));
    }
  };

  it('Forepay reconciliation', async () => {
    await pool.setCoverageForepayPct(60_00);
    await checkForepay();
    await pool.setCoverageForepayPct(80_00);
    await checkForepay();
    await pool.setCoverageForepayPct(90_00);
    await checkForepay();
  });

  const claim = async (claimPct: number, flushMCD: boolean) => {
    const forepayPct = (await pool.getPoolParams()).coverageForepayPct / 100;
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);
    expect(await cc.balanceOf(user.address)).eq(0);

    const drawdown = await collectAvailableDrawdown();
    expect(drawdown).eq(demanded.mul(drawdownPct).div(100)).gt(0);

    if (flushMCD) {
      await premFund.swapAsset(pool.address, user.address, user.address, drawdown, cc.address, 0);
      expect(await cc.balanceOf(user.address)).eq(drawdown);
      expect(await collectAvailableDrawdown()).eq(0);
    }

    for (let i = 0; i < insureds.length; i++) {
      await insureds[i].reconcileWithInsurers(0, 0, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });
    }

    let availableCC = await cc.balanceOf(pool.address);
    expect(availableCC).eq(demanded.mul(100 - ((flushMCD ? drawdownPct : 0) + forepayPct)).div(100));

    let lockedFromClaim = BigNumber.from(0);
    for (let i = 0; i < insureds.length; i++) {
      const insured = insureds[i];
      const receiver = createRandomAddress();
      const totalCovered = (await poolIntf.receivableDemandedCoverage(insured.address, 0)).coverage.totalCovered;
      availableCC = (await cc.balanceOf(pool.address)).sub(lockedFromClaim);
      availableCC = availableCC.gt(0) ? availableCC : BigNumber.from(0);

      const missing = totalCovered.mul(claimPct - forepayPct).div(100);
      const extra = availableCC.gt(missing) ? missing : availableCC;
      const expectedPayout = totalCovered.mul(forepayPct).div(100).add(extra);

      const requestAmount = claimPct === 100 ? MAX_UINT : totalCovered.mul(claimPct).div(100);
      await insured.cancelCoverage(receiver, requestAmount, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });
      {
        expect(await cc.balanceOf(receiver)).eq(expectedPayout);
      }

      lockedFromClaim = lockedFromClaim.add(totalCovered.mul(100 - claimPct).div(100));
    }

    const { coverage } = await pool.getTotals();
    expect(coverage.totalDemand).eq(0);
    expect(coverage.totalCovered).eq(0);
  };

  const makeTest = (claimPct: number, forepayPct: number, flushMCD: boolean) => {
    const title = `Claim ${claimPct}%, forepay ${forepayPct}%${flushMCD ? ', MCD depleted' : ''}`;
    return it(title, async () => {
      await pool.setCoverageForepayPct(forepayPct * 100);
      await claim(claimPct, flushMCD);
    });
  };

  for (let claimAmt = 100; claimAmt > 60; claimAmt -= 10) {
    for (let forepay = 90; forepay > 70; forepay -= 10) {
      makeTest(claimAmt, forepay, true);
      makeTest(claimAmt, forepay, false);
    }
  }

  it('Premium debt', async () => {
    await insureds[0].cancelAllCoverageDemand({ gasLimit: testEnv.underCoverage ? 2000000 : undefined });
    await insureds[1].cancelAllCoverageDemand({ gasLimit: testEnv.underCoverage ? 2000000 : undefined });
    await insureds[2].cancelAllCoverageDemand({ gasLimit: testEnv.underCoverage ? 2000000 : undefined });

    await pool.setPremiumDistributor(premFund.address);
    await pool.setCoverageForepayPct(80_00);

    let demand = (await joinPool(10 * 100)).totalDemand;
    demand = demand.add((await joinPool(10 * 100)).totalDemand);
    demand = demand.add((await joinPool(10 * 100)).totalDemand);

    let ratePerInsured = BigNumber.from(demandPerInsured).mul(rate).div(WAD);
    let t = (await cc.mintAndTransfer(user.address, pool.address, demand, 0)).timestamp;
    t = t === undefined ? await currentTime() : t;

    for (let i = insureds.length - 3; i < insureds.length; i++) {
      await premFund.setPrice(await insureds[i].premiumToken(), WAD);
      await insureds[i].reconcileWithInsurers(0, 0, { gasLimit: testEnv.underCoverage ? 2000000 : undefined });
    }

    let insured = insureds[insureds.length - 1];
    let receiver = createRandomAddress();
    await advanceBlock((await currentTime()) + 20);
    let t2 = (
      await insured.cancelCoverage(receiver, MAX_UINT, { gasLimit: testEnv.underCoverage ? 2000000 : undefined })
    ).timestamp;
    t2 = t2 === undefined ? await currentTime() : t2;

    let debt = ratePerInsured.mul(t2 - t);
    expect(await cc.balanceOf(receiver)).lte(BigNumber.from(demandPerInsured).sub(debt));

    await advanceBlock((await currentTime()) + 120);
    insured = insureds[insureds.length - 2];
    receiver = createRandomAddress();
    t2 = (await insured.cancelCoverage(receiver, MAX_UINT, { gasLimit: testEnv.underCoverage ? 2000000 : undefined }))
      .timestamp;
    t2 = t2 === undefined ? await currentTime() : t2;

    debt = ratePerInsured.mul(t2 - t);
    expect(await cc.balanceOf(receiver)).lte(BigNumber.from(demandPerInsured).sub(debt));

    const t3 = t2;
    const drawdown = await collectAvailableDrawdown();
    await premFund.swapAsset(pool.address, user.address, user.address, drawdown, cc.address, 0, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    insured = insureds[insureds.length - 3];
    receiver = createRandomAddress();
    t2 = (await insured.cancelCoverage(receiver, MAX_UINT, { gasLimit: testEnv.underCoverage ? 2000000 : undefined }))
      .timestamp;
    t2 = t2 === undefined ? await currentTime() : t2;
    debt = ratePerInsured.mul(t3 - t);
    ratePerInsured = BigNumber.from(demandPerInsured).sub(drawdown).mul(rate).div(WAD);
    debt = debt.add(ratePerInsured.mul(t2 - t3));

    // expect(await cc.balanceOf(receiver)).lt(BigNumber.from(demandPerInsured).sub(debt).sub(drawdown));
  });
});
