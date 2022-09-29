import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { MAX_UINT, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
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

    await reinvest.enableStrategy(strat.address, false);
    await expect(reinvest.pushTo(token.address, cf.address, strat.address, amount)).reverted;
    await reinvest.enableStrategy(strat.address, true);
    await reinvest.pushTo(token.address, cf.address, strat.address, amount);

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
  });

  it('Deposit yield into collateral fund', async () => {
    const amount = 1e5;

    await cf.connect(user).invest(user.address, token.address, amount, insurer.address);
    await reinvest.pushTo(token.address, cf.address, strat.address, amount);
    await strat.connect(user).deltaYield(token.address, amount);

    await reinvest.pullYieldFrom(token.address, strat.address, cf.address, amount);
    // expect(await cc.balanceOf(insurer.address)).eq(amount*2);

    // Updates YieldBase.sol yield balance
    // await insurer.collectDrawdownPremium();
    // console.log(await cc.balancesOf(insurer.address));
  });

  // it('Strategy loss', async () => { });
});
