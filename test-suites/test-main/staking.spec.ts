import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { advanceBlock, currentTime, getSigners } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { NoYieldToken, MockStable, MockPremiumEarningPool } from '../../types';
import { IUniswapV2Router01Factory } from '../../types/IUniswapV2Router01Factory';
import { IUniswapV2FactoryFactory } from '../../types/IUniswapV2FactoryFactory';
import { IUniswapV2PairFactory } from '../../types/IUniswapV2PairFactory';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { getAddress } from 'ethers/lib/utils';

makeSharedStateSuite('Collateral Fund Stable', (testEnv: TestEnv) => {
  let NYT: NoYieldToken;
  let pool: MockPremiumEarningPool;
  let stable: MockStable;
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;

  let rate = 1; //1 CC per second per 1e18 "invested"
  let decimals = BigNumber.from(10).pow(18);
  let uniswapv2_router_address = '0xf164fC0Ec4E93095b804a4795bBe1e041497b92a';
  let uniswapv2_factory_address = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';

  let NYTbalanceOf;
  let NYTbalanceOfA;

  before(async () => {
    [depositor1, depositor2] = await getSigners();

    pool = await Factories.MockPremiumEarningPool.deploy('Index Pool', 'IP', 18);
    NYT = await Factories.NoYieldToken.deploy('NoYield Index Pool', 'NYT-IP', 18, pool.address);
    stable = await Factories.MockStable.deploy();

    NYTbalanceOf = NYT['balanceOf(address)'];
    NYTbalanceOfA = NYT['balanceOfA(address,address)'];

    //Approvals
    await stable.connect(depositor1).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));
    await stable.connect(depositor2).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));
    await NYT.connect(depositor1).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));
    await NYT.connect(depositor2).approve(uniswapv2_router_address, BigNumber.from(1000000).mul(decimals));

    await pool.setPremiumRate(rate);
  });

  it('Deposit into NYT', async () => {
    let unscaled = 100;
    let amt = BigNumber.from(unscaled).mul(decimals);
    await pool.mint(depositor1.address, amt);
    expect(await pool.balanceOf(depositor1.address)).eq(amt);

    //Advance by 10 seconds
    await advanceBlock((await currentTime()) + 10);
    expect(await (await pool.interestRate(depositor1.address)).accumulated).eq(rate * unscaled * 10);

    //Deposit into NYT
    await NYT.connect(depositor1).wrap(amt);
    expect(await pool.balanceOf(depositor1.address)).eq(0);
    expect(await NYTbalanceOf(depositor1.address)).eq(amt);

    //NYT contract should now be getting premium
    await advanceBlock((await currentTime()) + 10);
    expect(await (await pool.interestRate(NYT.address)).accumulated).eq(rate * unscaled * 10);
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
        NYT.address,
        stable.address,
        amt,
        amt,
        amtMin,
        amtMin,
        depositor1.address,
        (await currentTime()) + 100
      );

    let pair = await IUniswapV2PairFactory.connect(await factory.getPair(NYT.address, stable.address), depositor1);
    expect(await NYTbalanceOf(pair.address)).eq(amt);
    await NYT.connect(depositor1).addToWhitelist(pair.address, pair.address);

    //Approve LP tokens for transfer to contract
    await pair.connect(depositor1).approve(NYT.address, BigNumber.from(2).pow(256).sub(1));
    await NYT.connect(depositor1).stake(pair.address, await pair.balanceOf(depositor1.address));

    expect(await NYT.totalStaked()).eq(amt);
    await advanceBlock((await currentTime()) + 10);
    console.log(await NYT.getPoolPremium(pair.address));
    console.log(await NYT.earned(depositor1.address, pair.address));
  });
});
