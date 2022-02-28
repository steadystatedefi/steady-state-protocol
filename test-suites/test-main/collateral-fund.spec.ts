import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { RAY } from '../../helpers/constants';
import { createRandomAddress, getSigners } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import {
  CollateralFundStable,
  DepositTokenERC20Adapter,
  DepositTokenERC20AdapterFactory,
  ERC20Factory,
  MockTreasuryStrategy,
  MockTreasuryStrategyFactory,
  MockWeightedPool,
} from '../../types';
import { MockStable } from '../../types';
import { tEthereumAddress } from '../../helpers/types';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getAddress } from 'ethers/lib/utils';
import BigNumber from 'bignumber.js';

makeSharedStateSuite('Collateral Fund Stable', (testEnv: TestEnv) => {
  const unitSize = 1000;
  let fund: CollateralFundStable;
  let pool: MockWeightedPool;
  let stable: MockStable;
  let strategy: MockTreasuryStrategy;
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;

  let balanceOf;
  let dBalanceOf;

  //TODO: Insurer type, add it in another test

  before(async () => {
    stable = await Factories.MockStable.deploy();
    fund = await Factories.CollateralFundStable.deploy('STABLE-FUND');
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    pool = await Factories.MockWeightedPool.deploy(fund.address, unitSize, 18, extension.address);
    await fund.addInsurer(pool.address);
    expect(await fund.isInsurer(pool.address));

    strategy = await Factories.MockTreasuryStrategy.deploy(fund.address, stable.address);
    await fund.AddStrategy(strategy.address, stable.address, 1000000);
    //expect(await fund.treasuryAllowanceOf(strategy.address, stable.address)).eq(1000000);

    [depositor1, depositor2] = await getSigners();
    await stable.mint(depositor1.address, 1000);
    await stable.mint(depositor2.address, 1000);
    await stable.connect(depositor1).approve(fund.address, 100000000000000);
    await stable.connect(depositor2).approve(fund.address, 100000000000000);
    balanceOf = fund['balanceOf(address)'];
    dBalanceOf = fund['balanceOf(address,address)'];

    console.log('Stablecoin deployed at: ', stable.address);
    console.log('Collateral fund deployed at: ', fund.address);
    console.log('Treasury Strategy deployed at: ');
  });

  it('Add stablecoin to deposit tokens', async () => {
    await fund.connect(depositor1).addDepositToken(stable.address);
    let deposits = await fund.getDepositsAccepted();
    expect(deposits[0]).eq(stable.address);
    let stableID = await (await fund.getId(stable.address)).toBigInt();
    console.log('Stable ERC1155 ID: ', stableID);

    let stableDT = await fund.getAddress(stable.address);
    //let stableDT = await fund.CreateToken(stable.address, 'Stable DT', 'SDT')
    console.log('StableDT: ', stableDT);
    expect(stableDT.toLowerCase()).eq('0x' + stableID.toString(16));
  });

  it('Deposit stable token', async () => {
    let amt = 500;
    let balance,
      balanceBefore,
      dtbalance = 0;

    /** Deposit to self **/
    await fund.connect(depositor1).deposit(stable.address, amt, depositor1.address, 0);
    balance = await (await balanceOf(depositor1.address)).toNumber();
    expect(balance).eq(amt);
    dtbalance = await (await dBalanceOf(depositor1.address, stable.address)).toNumber();
    expect(dtbalance).eq(amt);

    amt = 300;
    await fund.connect(depositor2).deposit(stable.address, amt, depositor2.address, 0);
    balance = await (await balanceOf(depositor2.address)).toNumber();
    expect(balance).eq(amt);

    /** Deposit to other **/
    amt = 200;
    balanceBefore = await (await balanceOf(depositor1.address)).toNumber();
    await fund.connect(depositor2).deposit(stable.address, amt, depositor1.address, 0);
    balance = await balanceOf(depositor1.address);
    expect(balance).eq(amt + balanceBefore);
  });

  it('Withdraw stable token', async () => {
    let amt = 300;
    let balanceCC,
      balanceDT,
      balanceCCBefore,
      balanceDTBefore = 0;
    balanceCCBefore = await (await balanceOf(depositor1.address)).toNumber();
    balanceDTBefore = await (await dBalanceOf(depositor1.address, stable.address)).toNumber();
    console.log(await fund.healthFactorOf(depositor1.address));

    await fund.connect(depositor1).withdraw(stable.address, amt, depositor1.address);
    balanceCC = await balanceOf(depositor1.address);
    balanceDT = await dBalanceOf(depositor1.address, stable.address);
    expect(balanceDT).eq(balanceDTBefore - amt);
    expect(balanceCC).eq(balanceCCBefore - amt);
  });

  it('Invest stable token', async () => {
    await fund.connect(depositor1).invest(pool.address, 100);
    //TODO: Test that the Weighted Pool credits this investor
  });

  it('Test Strategy', async () => {
    expect(await fund.redeemPerToken(stable.address, 100)).eq(100);
    let balance_underlying = await stable.balanceOf(fund.address);
    let all_tokens = await fund.numberOf(stable.address);
    expect(balance_underlying).eq(all_tokens);

    //Request borrow
    await strategy.Borrow(balance_underlying);
    expect(await stable.balanceOf(strategy.address)).eq(balance_underlying);

    //Earn 10% yield on the tokens
    let earn = balance_underlying.mul(10).div(100);
    await strategy.MockYield(earn);

    all_tokens = await fund.numberOf(stable.address);
    expect(all_tokens).eq(balance_underlying.add(earn));
    expect(await fund.redeemPerToken(stable.address, 100)).eq(110);

    //Make a withdraw when 100% of funds are deployed, fund must request return from strategies
    let amt = 100;
    await fund.withdraw(stable.address, amt, depositor1.address);
  });

  it('Transfer Adapter', async () => {
    await fund.CreateToken(stable.address, 'CF Stable', 'CF-Stable');
    let addr = await fund.getAddress(stable.address);
    let adapter = Factories.DepositTokenERC20Adapter.attach(addr);
    expect(await adapter.totalSupply()).eq(await fund['totalSupply(address)'](stable.address));

    let depositor1_balance = await adapter.balanceOf(depositor1.address);
    let depositor2_balance = await adapter.balanceOf(depositor2.address);
    expect(depositor1_balance).eq(await dBalanceOf(depositor1.address, stable.address));
    expect(depositor2_balance).eq(await dBalanceOf(depositor2.address, stable.address));

    let amt = 25;
    await adapter.connect(depositor2).transfer(depositor1.address, amt);
    expect(await adapter.balanceOf(depositor1.address)).eq(depositor1_balance.add(amt));
    expect(await adapter.balanceOf(depositor2.address)).eq(depositor2_balance.sub(amt));
  });
});
