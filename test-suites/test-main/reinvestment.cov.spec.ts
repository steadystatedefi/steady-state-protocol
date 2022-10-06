import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { MAX_UINT, WAD } from '../../helpers/constants';
import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import { advanceBlock, currentTime } from '../../helpers/runtime-utils';
import {
  MockCollateralCurrency,
  MockCollateralFund,
  MockERC20,
  MockImperpetualPool,
  MockReinvestManager,
  MockStrategy,
} from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Reinvestment', (testEnv: TestEnv) => {
  let reinvest: MockReinvestManager;
  let cc: MockCollateralCurrency;
  let cf: MockCollateralFund;
  let strat: MockStrategy;
  let token: MockERC20;
  let user: SignerWithAddress;
  let insurer: MockImperpetualPool;

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
    cf = await Factories.MockCollateralFund.deploy(cc.address);
    reinvest = await Factories.MockReinvestManager.deploy(cc.address);
    strat = await Factories.MockStrategy.deploy();
    token = await Factories.MockERC20.deploy('Mock', 'MCK', 18);

    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), 1e7, cc.address);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), 1e7, cc.address);
    insurer = await Factories.MockImperpetualPool.deploy(extension.address, joinExtension.address);

    await cc.registerLiquidityProvider(cf.address);
    await cc.registerInsurer(insurer.address);
    await cc.setBorrowManager(reinvest.address);
    await cf.addAsset(token.address, zeroAddress());
    await cf.setPriceOf(token.address, WAD);
    await reinvest.enableStrategy(strat.address, true);

    await token.mint(user.address, WAD);
    await token.connect(user).approve(cf.address, MAX_UINT);
    await token.connect(user).approve(strat.address, MAX_UINT);
  });

  it('Push/pull funds for strategy', async () => {
    const amount = 1e5;

    await cf.connect(user).invest(user.address, token.address, amount, insurer.address);
    expect(await token.balanceOf(cf.address)).eq(amount);
    expect(await cc.totalSupply()).eq(amount);

    await Events.StrategyEnabled.waitOne(reinvest.enableStrategy(strat.address, false), (ev) => {
      expect(ev.strategy).eq(strat.address);
      expect(ev.enable).eq(false);
    });
    {
      expect((await reinvest.strategies()).length).eq(0);
      await expect(reinvest.pushTo(token.address, cf.address, strat.address, amount)).reverted;
    }

    await Events.StrategyEnabled.waitOne(reinvest.enableStrategy(strat.address, true), (ev) => {
      expect(ev.strategy).eq(strat.address);
      expect(ev.enable).eq(true);
    });
    {
      expect((await reinvest.strategies())[0]).eq(strat.address);
      await reinvest.pushTo(token.address, cf.address, strat.address, amount);
    }

    expect(await token.balanceOf(strat.address)).eq(amount);
    await strat.connect(user).deltaYield(token.address, amount);
    let [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, strat.address);
    expect(borrowedBal).eq(amount);
    expect(repayableBal).eq(amount * 2);

    await reinvest.pullFrom(token.address, strat.address, cf.address, amount);
    expect(await token.balanceOf(cf.address)).eq(amount);
    [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, strat.address);
    expect(borrowedBal).eq(0);
    expect(repayableBal).eq(amount);

    // Since there is no borrowed balance, the pull yield method must be used
    await reinvest.pullFrom(token.address, strat.address, cf.address, MAX_UINT);
    [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, strat.address);
    expect(borrowedBal).eq(0);
    expect(repayableBal).eq(amount);
  });

  it('Deposit yield into collateral fund', async () => {
    const amount = 1e5;

    await cf.connect(user).invest(user.address, token.address, amount, insurer.address);
    await reinvest.pushTo(token.address, cf.address, strat.address, amount);
    await reinvest.pullYieldFrom(token.address, strat.address, cf.address, amount);
    expect(await token.balanceOf(cf.address)).eq(0);
    await strat.connect(user).deltaYield(token.address, amount);

    await reinvest.pullYieldFrom(token.address, strat.address, cf.address, amount);
    const [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, strat.address);
    {
      expect(borrowedBal).eq(amount);
      expect(repayableBal).eq(amount);
      expect(await cc.balanceOf(insurer.address)).eq(amount);
      expect(await token.balanceOf(cf.address)).eq(amount);
    }

    await insurer.collectDrawdownPremium();
    expect(await cc.balanceOf(insurer.address)).eq(amount * 2);

    await advanceBlock((await currentTime()) + 10);
    await strat.connect(user).deltaYield(token.address, amount);
    await reinvest.pullYieldFrom(token.address, strat.address, cf.address, amount);
    await insurer.collectDrawdownPremium();
    expect(await cc.balanceOf(insurer.address)).eq(amount * 3);
    expect(await token.balanceOf(cf.address)).eq(amount * 2);
  });

  it('Strategy loss', async () => {
    const amount = 1e5;
    const loss = 3e4;

    await cf.connect(user).invest(user.address, token.address, amount, insurer.address);
    await reinvest.pushTo(token.address, cf.address, strat.address, amount);
    await strat.connect(user).deltaYield(token.address, loss * -1);

    await reinvest.pullFrom(token.address, strat.address, cf.address, amount);
    let [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, strat.address);
    expect(borrowedBal).eq(loss);
    expect(repayableBal).eq(0);

    await token.connect(user).approve(reinvest.address, loss);
    await reinvest.repayLossFrom(token.address, user.address, strat.address, cf.address, loss);
    [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, strat.address);
    expect(borrowedBal).eq(0);
    expect(repayableBal).eq(0);
  });

  it('Two insurers', async () => {
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), 1e7, cc.address);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), 1e7, cc.address);
    const insurer2 = await Factories.MockImperpetualPool.deploy(extension.address, joinExtension.address);
    await cc.registerInsurer(insurer2.address);

    const amountPerInsurer = 1e5;

    await cf.connect(user).invest(user.address, token.address, amountPerInsurer, insurer.address);
    await cf.connect(user).invest(user.address, token.address, amountPerInsurer, insurer2.address);
    expect(await token.balanceOf(cf.address)).eq(amountPerInsurer * 2);

    await reinvest.pushTo(token.address, cf.address, strat.address, amountPerInsurer * 2);
    await strat.connect(user).deltaYield(token.address, amountPerInsurer); // 50% yield
    await reinvest.pullYieldFrom(token.address, strat.address, cf.address, MAX_UINT);

    expect(await token.balanceOf(cf.address)).eq(amountPerInsurer);

    expect(await cc.balanceOf(insurer.address)).eq(amountPerInsurer);
    await insurer.collectDrawdownPremium();
    expect(await cc.balanceOf(insurer.address)).eq(amountPerInsurer * 1.5);

    expect(await cc.balanceOf(insurer2.address)).eq(amountPerInsurer);
    await insurer2.collectDrawdownPremium();
    expect(await cc.balanceOf(insurer2.address)).eq(amountPerInsurer * 1.5);
  });

  it('Call strategy', async () => {
    let selector = strat.interface.encodeFunctionData('testCall');
    await expect(reinvest.callStrategy(user.address, selector)).reverted;
    await expect(reinvest.callStrategy(strat.address, selector)).reverted;

    await strat.setCallSuccess(true);
    await reinvest.callStrategy(strat.address, selector);
    selector = strat.interface.encodeFunctionData('connectAssetAfter', [token.address]);
    await expect(reinvest.callStrategy(strat.address, selector)).reverted;
  });

  it('Aave strategy', async () => {
    const aToken = await Factories.MockERC20.deploy('aToken', 'AA', 18);
    const aPool = await Factories.MockAavePoolV3.deploy(aToken.address);
    const aStrat = await Factories.AaveStrategy.deploy(reinvest.address, aPool.address, 3);
    await reinvest.enableStrategy(aStrat.address, true);
    await token.approve(aStrat.address, MAX_UINT);

    const amount = 1e10;

    await cf.connect(user).invest(user.address, token.address, amount, insurer.address);
    await reinvest.pushTo(token.address, cf.address, aStrat.address, amount);
    let [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, aStrat.address);
    {
      expect(await aToken.balanceOf(aStrat.address)).eq(amount);
      expect(await token.balanceOf(cf.address)).eq(0);
      expect(borrowedBal).eq(amount);
      expect(repayableBal).eq(amount);
    }

    const stratYield = 1e9; // +10%
    await token.mint(aPool.address, stratYield);
    await aPool.addYieldToUser(aStrat.address, stratYield);
    [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, aStrat.address);
    {
      expect(await aStrat.investedValueOf(token.address)).eq(amount + stratYield);
      expect(borrowedBal).eq(amount);
      expect(repayableBal).eq(amount + stratYield);
    }

    await reinvest.pullYieldFrom(token.address, aStrat.address, cf.address, MAX_UINT);
    [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, aStrat.address);
    {
      expect(await aToken.balanceOf(aStrat.address)).eq(amount);
      expect(await token.balanceOf(cf.address)).eq(stratYield);
      expect(await aStrat.investedValueOf(token.address)).eq(amount);
      expect(borrowedBal).eq(amount);
      expect(repayableBal).eq(amount);
    }

    await insurer.collectDrawdownPremium();
    expect(await cc.balanceOf(insurer.address)).eq(amount + stratYield);

    await reinvest.pullFrom(token.address, aStrat.address, cf.address, MAX_UINT);
    [borrowedBal, repayableBal] = await reinvest.balancesOf(token.address, aStrat.address);
    {
      expect(await aToken.balanceOf(aStrat.address)).eq(0);
      expect(await token.balanceOf(cf.address)).eq(amount + stratYield);
      expect(await token.balanceOf(aStrat.address)).eq(0);
      expect(await aStrat.investedValueOf(token.address)).eq(0);
      expect(borrowedBal).eq(0);
      expect(repayableBal).eq(0);
    }

    await insurer.collectDrawdownPremium();
    expect(await cc.balanceOf(insurer.address)).eq(amount + stratYield);
  });

  it('Investment events', async () => {
    await token.approve(reinvest.address, MAX_UINT);
    const amount = 1e5;
    await cf.connect(user).invest(user.address, token.address, amount, insurer.address);

    await Events.LiquidityInvested.waitOne(reinvest.pushTo(token.address, cf.address, strat.address, amount), (ev) => {
      expect(ev.amount).eq(amount);
      expect(ev.asset).eq(token.address);
      expect(ev.fromFund).eq(cf.address);
      expect(ev.toStrategy).eq(strat.address);
    });

    await strat.connect(user).deltaYield(token.address, amount);
    await Events.LiquidityYieldPulled.waitOne(
      reinvest.pullYieldFrom(token.address, strat.address, cf.address, amount),
      (ev) => {
        expect(ev.amount).eq(amount);
        expect(ev.asset).eq(token.address);
        expect(ev.viaFund).eq(cf.address);
        expect(ev.fromStrategy).eq(strat.address);
      }
    );

    await strat.connect(user).deltaYield(token.address, (amount / 2) * -1);
    await Events.LiquidityDivested.waitOne(
      reinvest.pullFrom(token.address, strat.address, cf.address, amount),
      (ev) => {
        expect(ev.amount).eq(amount / 2);
        expect(ev.asset).eq(token.address);
        expect(ev.toFund).eq(cf.address);
        expect(ev.fromStrategy).eq(strat.address);
      }
    );

    await Events.LiquidityLossPaid.waitOne(
      reinvest.repayLossFrom(token.address, user.address, strat.address, cf.address, amount / 2),
      (ev) => {
        expect(ev.amount).eq(amount / 2);
        expect(ev.asset).eq(token.address);
        expect(ev.viaFund).eq(cf.address);
        expect(ev.forStrategy).eq(strat.address);
      }
    );
  });
});
