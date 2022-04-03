import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { advanceBlock, currentTime, getSigners } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { TradeableToken, GenericStaking, MockStable, MockPremiumEarningPool } from '../../types';
import { IUniswapV2Router01Factory } from '../../types/IUniswapV2Router01Factory';
import { IUniswapV2FactoryFactory } from '../../types/IUniswapV2FactoryFactory';
import { IUniswapV2PairFactory } from '../../types/IUniswapV2PairFactory';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber } from 'ethers';

makeSharedStateSuite('Collateral Fund Stable', (testEnv: TestEnv) => {
  let trade: TradeableToken;
  let pool: MockPremiumEarningPool;
  let staker: GenericStaking;
  let stable: MockStable;
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;

  let rate = 1; //1 CC per second per 1e18 "invested"
  let decimals = BigNumber.from(10).pow(18);
  let uniswapv2_router_address = '0xf164fC0Ec4E93095b804a4795bBe1e041497b92a';
  let uniswapv2_factory_address = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';

  let tradebalanceOf;
  let tradebalanceOfA;

  before(async () => {
    [depositor1, depositor2] = await getSigners();

    pool = await Factories.MockPremiumEarningPool.deploy('Index Pool', 'IP', 18);
    trade = await Factories.TradeableToken.deploy('Tradeable Index Pool', 'trade-IP', 18, pool.address);
    stable = await Factories.MockStable.deploy();

    tradebalanceOf = trade['balanceOf(address)'];
    tradebalanceOfA = trade['balanceOfA(address,address)'];

    //Approvals
    await stable.connect(depositor1).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));
    await stable.connect(depositor2).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));
    await trade.connect(depositor1).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));
    await trade.connect(depositor2).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));

    await pool.setPremiumRate(rate);
  });

  it('Deposit into trade', async () => {
    let unscaled = 100;
    let amt = BigNumber.from(unscaled).mul(decimals);
    await pool.mint(depositor1.address, amt);
    expect(await pool.balanceOf(depositor1.address)).eq(amt);

    //Advance by 10 seconds
    await advanceBlock((await currentTime()) + 10);
    const interestRate = await pool.interestRate(depositor1.address);
    expect(interestRate.accumulated).eq(rate * unscaled * 10);

    //Deposit into trade
    await trade.connect(depositor1).wrap(amt);
    expect(await pool.balanceOf(depositor1.address)).eq(0);
    expect(await tradebalanceOf(depositor1.address)).eq(amt);

    //trade contract should now be getting premium
    await advanceBlock((await currentTime()) + 10);
    expect(await (await pool.interestRate(trade.address)).accumulated).eq(rate * unscaled * 10);
  });

  it('Deposit into LP and stake', async () => {
    let router = await IUniswapV2Router01Factory.connect(uniswapv2_router_address, depositor1);
    let factory = await IUniswapV2FactoryFactory.connect(uniswapv2_factory_address, depositor1);

    //Mint stable
    let unscaled = 1000;
    let amt = BigNumber.from(unscaled).mul(decimals);
    await stable.mint(depositor1.address, amt);

    unscaled = 100;
    amt = BigNumber.from(unscaled).mul(decimals);
    let amtMin = amt.mul(98).div(100);
    await router
      .connect(depositor1)
      .addLiquidity(
        trade.address,
        stable.address,
        amt,
        amt,
        amtMin,
        amtMin,
        depositor1.address,
        (await currentTime()) + 100
      );

    let pair = await IUniswapV2PairFactory.connect(await factory.getPair(trade.address, stable.address), depositor1);
    expect(await tradebalanceOf(pair.address)).eq(amt);

    staker = await Factories.GenericStakingPool.deploy('STK-UNI', 'SUNI', 18, trade.address, pair.address);
    await trade.connect(depositor1).addToWhitelist(pair.address, staker.address);

    //Approve LP tokens for transfer to contract
    await pair.connect(depositor1).approve(staker.address, BigNumber.from(2).pow(256).sub(1));
    await staker.connect(depositor1).stake(await pair.balanceOf(depositor1.address));

    await advanceBlock((await currentTime()) + 10);
    console.log(await trade.getPoolEarned(pair.address));
    console.log(await staker.earned(depositor1.address));
  });
});
