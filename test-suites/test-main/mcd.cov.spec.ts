import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish } from 'ethers';

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
  let demanded: BigNumberish;

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

    demanded = BigNumber.from(0);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
  });

  it('Drawdown User Premium', async () => {
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);

    let drawdown = await pool.callStatic.collectDrawdownPremium();
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
      expect(await pool.callStatic.collectDrawdownPremium()).eq(drawdown.sub(amtSwap));
      expect(await pool.balanceOf(user.address)).lte(balance.sub(tokenSwap));
      expect(await cc.balanceOf(user.address)).eq(ccbalance.add(amtSwap));
    }

    drawdown = await pool.callStatic.collectDrawdownPremium();

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
    // TODO should NOT cause overflow / underflow
    // expect(await premFund.callStatic.swapAsset(pool.address, user.address, user.address, amtSwap, cc.address, amtSwap)).eq(0);

    amtSwap = drawdown;
    tokenSwap = await valueToAmount(amtSwap, 1);
    await premFund.swapAsset(pool.address, user.address, user.address, amtSwap, cc.address, amtSwap);
    {
      expect(await pool.callStatic.collectDrawdownPremium()).eq(0);
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
    expect(await pool.callStatic.collectDrawdownPremium()).eq(amtMinted.mul(drawdownPct).div(100));
  });

  it('Cancel all coverage (MCD will cause not entire coverage to be paid out)', async () => {
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);
    expect(await cc.balanceOf(user.address)).eq(0);

    const drawdown = await pool.callStatic.collectDrawdownPremium();
    expect(drawdown).gt(0);
    await premFund.swapAsset(pool.address, user.address, user.address, drawdown, cc.address, 0);
    expect(await cc.balanceOf(user.address)).eq(drawdown);

    for (let i = 0; i < insureds.length; i++) {
      const insured = insureds[i];
      await insured.reconcileWithInsurers(0, 0);
      const receiver = createRandomAddress();
      const payoutAmount = (await poolIntf.receivableDemandedCoverage(insured.address, 0)).coverage.totalCovered;

      await insured.cancelCoverage(receiver, MAX_UINT);
      {
        const bal = await cc.balanceOf(receiver);
        // expect(bal).lte(payoutAmount);
        // expect(bal).gte(payoutAmount.mul(100 - drawdownPct).div(100));
        expect(bal).eq(payoutAmount.mul(100 - drawdownPct).div(100));
      }
    }

    const { coverage } = await pool.getTotals();
    expect(coverage.totalDemand).eq(0);
    expect(coverage.totalCovered).eq(0);
    expect(await pool.callStatic.collectDrawdownPremium()).eq(0);
  });
});
