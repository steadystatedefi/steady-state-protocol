import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { MAX_UINT, RAY } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { createRandomAddress } from '../../helpers/runtime-utils';
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
      4000 * unitSize,
      1e12,
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
      await insured.reconcileWithInsurers(0, 0);
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

  const claim = async (flushMCD: boolean, increment: boolean) => {
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);
    expect(await cc.balanceOf(user.address)).eq(0);

    const drawdown = await collectAvailableDrawdown();
    expect(drawdown).gt(0);

    if (flushMCD) {
      await premFund.swapAsset(pool.address, user.address, user.address, drawdown, cc.address, 0);
      expect(await cc.balanceOf(user.address)).eq(drawdown);
    }

    const insured = insureds[0];
    await insured.reconcileWithInsurers(0, 0);
    const receiver = createRandomAddress();
    const {
      coverage: { totalCovered },
    } = await poolIntf.receivableDemandedCoverage(insured.address, 0);

    const coverageForepayPct = (await pool.getPoolParams()).coverageForepayPct;
    expect(coverageForepayPct).gte(50_00);
    const payoutVariance = Math.round((100_00 - coverageForepayPct) / 2);
    expect(payoutVariance).gt(0);

    const payoutAmount = totalCovered
      .mul(coverageForepayPct + (increment ? payoutVariance : -payoutVariance))
      .div(1_00_00);

    await insured.cancelCoverage(receiver, payoutAmount);
    {
      const bal = await cc.balanceOf(receiver);
      expect(bal).eq(flushMCD && increment ? totalCovered.mul(coverageForepayPct).div(1_00_00) : payoutAmount);
    }
  };

  it('Claim slightly below the forepay', async () => claim(false, false));
  it('Claim slightly above the forepay', async () => claim(false, true));

  it('Claim slightly below the forepay, MCD depleted', async () => claim(true, false));
  it('Claim slightly above the forepay, MCD depleted', async () => claim(true, true));

  // TODO: Replace above claim method
  const claim2 = async (claimPct: number, flushMCD: boolean) => {
    const forepayPct = (await pool.getPoolParams()).coverageForepayPct / 100;
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);
    expect(await cc.balanceOf(user.address)).eq(0);

    const drawdown = await collectAvailableDrawdown();
    expect(drawdown).eq(demanded.mul(drawdownPct).div(100)).gt(0);

    if (flushMCD) {
      await premFund.swapAsset(pool.address, user.address, user.address, drawdown, cc.address, 0);
      expect(await cc.balanceOf(user.address)).eq(drawdown);
    }

    for (let i = 0; i < insureds.length; i++) {
      await insureds[i].reconcileWithInsurers(0, 0);
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

      const missing = claimPct >= forepayPct ? totalCovered.mul(claimPct - forepayPct).div(100) : 0;
      const extra = availableCC.gt(missing) ? missing : availableCC;
      const expectedPayout = totalCovered.mul(forepayPct).div(100).add(extra);

      const requestAmount = claimPct === 100 ? MAX_UINT : totalCovered.mul(claimPct).div(100);
      await insured.cancelCoverage(receiver, requestAmount);
      {
        expect(await cc.balanceOf(receiver)).eq(expectedPayout);
      }

      lockedFromClaim = lockedFromClaim.add(totalCovered.mul(100 - claimPct).div(100));
    }

    const { coverage } = await pool.getTotals();
    expect(coverage.totalDemand).eq(0);
    expect(coverage.totalCovered).eq(0);
    expect(await collectAvailableDrawdown()).eq(0);
  };

  const makeTest = (claimPct: number, forepayPct: number, flushMCD: boolean) => {
    const title = `Claim ${claimPct}%, forepay ${forepayPct}%${flushMCD ? ', MCD depleted' : ''}`;
    return it(title, async () => {
      await pool.setCoverageForepayPct(forepayPct * 100);
      await claim2(claimPct, flushMCD);
    });
  };

  // Claim 100%
  for (let i = 0; i < 3; i++) {
    makeTest(100, 90 - i * 10, true);
  }

  // Claim 90%
  for (let i = 0; i < 3; i++) {
    makeTest(90, 90 - i * 10, true);
  }

  // Claim 100%, no MCD
  for (let i = 0; i < 3; i++) {
    makeTest(100, 90 - i * 10, false);
  }

  // Claim 90%, no MCD
  for (let i = 0; i < 3; i++) {
    makeTest(90, 90 - i * 10, false);
  }
});
