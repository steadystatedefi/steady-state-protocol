import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { RAY } from '../../helpers/constants';
import { createRandomAddress, getSigners } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { CollateralFundStable, MockWeightedPool } from '../../types';
import { MockStable } from '../../types';
import { tEthereumAddress } from '../../helpers/types';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getAddress } from 'ethers/lib/utils';

makeSharedStateSuite('Collateral Fund Stable', (testEnv: TestEnv) => {
  const unitSize = 1000;
  let fund: CollateralFundStable;
  let pool: MockWeightedPool;
  let stable: MockStable;
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

    [depositor1, depositor2] = await getSigners();
    await stable.mint(depositor1.address, 1000);
    await stable.mint(depositor2.address, 1000);
    await stable.connect(depositor1).approve(fund.address, 100000000000000);
    await stable.connect(depositor2).approve(fund.address, 100000000000000);
    balanceOf = fund['balanceOf(address)'];
    dBalanceOf = fund['balanceOf(address,address)'];

    console.log('Stablecoin deployed at: ', stable.address);
    console.log('Collateral fund deployed at: ', fund.address);
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
});
