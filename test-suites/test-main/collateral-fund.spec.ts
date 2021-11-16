import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { RAY } from '../../helpers/constants';
import { createRandomAddress, getSigners } from '../../helpers/runtime-utils';
import { Factories } from '../../helpers/contract-types';
import { CollateralFundStable, DepositToken, DepositTokenFactory } from '../../types';
import { MockStable } from '../../types';
import { tEthereumAddress } from '../../helpers/types';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

makeSharedStateSuite('Collateral Fund Stable', (testEnv: TestEnv) => {
  const unitSize = 1000;
  let subj: CollateralFundStable;
  let stable: MockStable;
  let stableDT: DepositToken;
  let depositor1: SignerWithAddress;
  let depositor2: SignerWithAddress;
  //TODO: Insurer type, add it in another test

  before(async () => {
    stable = await Factories.MockStable.deploy();
    subj = await Factories.CollateralFundStable.deploy('STABLE-FUND', 'CC');
    [depositor1, depositor2] = await getSigners();
    await stable.mint(depositor1.address, 1000);
    await stable.mint(depositor2.address, 1000);
    await stable.connect(depositor1).approve(subj.address, 100000000000000);
    await stable.connect(depositor2).approve(subj.address, 100000000000000);

    console.log('Stablecoin deployed at: ', stable.address);
    console.log('Collateral fund deployed at: ', subj.address);
  });

  it('Add stablecoin to deposit tokens', async () => {
    await subj.connect(depositor1).addDepositToken(stable.address);
    //console.log(await subj.getDepositTokens());
    let deposits = await subj.getDepositTokens();
    expect(deposits[0]).eq(stable.address);
    stableDT = Factories.DepositToken.attach(await subj.getDepositTokenOf(stable.address));
  });

  it('Deposit stable token', async () => {
    let amt = 500;
    let balance,
      balanceBefore,
      dtbalance = 0;

    /** Deposit to self **/
    await subj.connect(depositor1).deposit(stable.address, amt, depositor1.address, 0);
    balance = await (await subj.balanceOf(depositor1.address)).toNumber();
    expect(balance).eq(amt);
    dtbalance = await (await stableDT.balanceOf(depositor1.address)).toNumber();
    expect(dtbalance).eq(amt);

    amt = 300;
    await subj.connect(depositor2).deposit(stable.address, amt, depositor2.address, 0);
    balance = await (await subj.balanceOf(depositor2.address)).toNumber();
    expect(balance).eq(amt);

    /** Deposit to other **/
    amt = 200;
    balanceBefore = await (await subj.balanceOf(depositor1.address)).toNumber();
    await subj.connect(depositor2).deposit(stable.address, amt, depositor1.address, 0);
    balance = await subj.balanceOf(depositor1.address);
    expect(balance).eq(amt + balanceBefore);
  });

  it('Withdraw stable token', async () => {
    let amt = 300;
    let balanceCC,
      balanceDT,
      balanceCCBefore,
      balanceDTBefore = 0;
    balanceCCBefore = await (await subj.balanceOf(depositor1.address)).toNumber();
    balanceDTBefore = await (await stableDT.balanceOf(depositor1.address)).toNumber();
    console.log(await subj.healthFactorOf(depositor1.address));

    await subj.connect(depositor1).withdraw(stable.address, amt, depositor1.address);
    balanceCC = await subj.balanceOf(depositor1.address);
    balanceDT = await stableDT.balanceOf(depositor1.address);
    expect(balanceDT).eq(balanceDTBefore - amt);
    expect(balanceCC).eq(balanceCCBefore - amt);
  });

  it('Invest stable token', async () => {});
});
