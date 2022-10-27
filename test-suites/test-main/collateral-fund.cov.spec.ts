import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { MAX_UINT, WAD } from '../../helpers/constants';
import { ProtocolErrors } from '../../helpers/contract-errors';
import { Factories } from '../../helpers/contract-types';
import { MockCollateralFund, MockCollateralCurrency } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Collateral fund', (testEnv: TestEnv) => {
  let cc: MockCollateralCurrency;
  let token0: MockCollateralCurrency;
  let fund: MockCollateralFund;
  let user0: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  before(async () => {
    user0 = testEnv.deployer;
    [user1, user2, user3] = testEnv.users;
    cc = await Factories.MockCollateralCurrency.deploy('Collateral Currency', '$CC');
    token0 = await Factories.MockCollateralCurrency.deploy('Collateral Asset', '$TK0');
    fund = await Factories.MockCollateralFund.deploy(cc.address);
    await cc.registerLiquidityProvider(fund.address);
    await token0.registerLiquidityProvider(user0.address);
    await fund.addAsset(token0.address, zeroAddress());
    await fund.setPriceOf(token0.address, WAD);

    await token0.mint(user1.address, WAD);
    await token0.mint(user2.address, WAD);
  });

  const APPROVED_DEPOSIT = 1;
  const APPROVED_INVEST = 2;
  const APPROVED_WITHDRAW = 4;

  it('Approvals', async () => {
    expect(await fund.isApprovedFor(user0.address, user1.address, APPROVED_DEPOSIT)).eq(false);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(0);

    await fund.setAllApprovalsFor(user1.address, APPROVED_INVEST + APPROVED_WITHDRAW);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(APPROVED_INVEST + APPROVED_WITHDRAW);

    expect(await fund.isApprovedFor(user0.address, user1.address, APPROVED_DEPOSIT)).eq(false);
    expect(await fund.isApprovedFor(user0.address, user1.address, APPROVED_INVEST)).eq(true);
    expect(await fund.isApprovedFor(user0.address, user1.address, APPROVED_WITHDRAW)).eq(true);

    await fund.setAllApprovalsFor(user1.address, 0);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(0);

    await fund.setApprovalsFor(user1.address, APPROVED_DEPOSIT + APPROVED_INVEST + APPROVED_WITHDRAW, true);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(
      APPROVED_DEPOSIT + APPROVED_INVEST + APPROVED_WITHDRAW
    );

    await fund.setApprovalsFor(user1.address, APPROVED_DEPOSIT, true);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(
      APPROVED_DEPOSIT + APPROVED_INVEST + APPROVED_WITHDRAW
    );

    await fund.setApprovalsFor(user1.address, APPROVED_DEPOSIT + APPROVED_INVEST, false);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(APPROVED_WITHDRAW);

    await fund.setApprovalsFor(user1.address, APPROVED_DEPOSIT, true);
    expect(await fund.getAllApprovalsFor(user0.address, user1.address)).eq(APPROVED_DEPOSIT + APPROVED_WITHDRAW);

    expect(await fund.getAllApprovalsFor(user0.address, user0.address)).eq(0);
    expect(await fund.getAllApprovalsFor(user0.address, user2.address)).eq(0);
    expect(await fund.getAllApprovalsFor(user1.address, user2.address)).eq(0);
    expect(await fund.getAllApprovalsFor(user2.address, user0.address)).eq(0);
    expect(await fund.getAllApprovalsFor(user2.address, user1.address)).eq(0);
  });

  it('Special approvals', async () => {
    expect(await fund.isApprovedFor(zeroAddress(), user1.address, APPROVED_DEPOSIT)).eq(false);
    expect(await fund.getAllApprovalsFor(zeroAddress(), user1.address)).eq(0);

    await fund.setSpecialRoles(user1.address, APPROVED_DEPOSIT);
    expect(await fund.isApprovedFor(zeroAddress(), user1.address, APPROVED_DEPOSIT)).eq(true);
    expect(await fund.getAllApprovalsFor(zeroAddress(), user1.address)).eq(APPROVED_DEPOSIT);
  });

  it('Deposit and withdraw', async () => {
    await token0.connect(user1).approve(fund.address, WAD);

    await expect(fund.connect(user1).deposit(user1.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.setSpecialRoles(user1.address, APPROVED_DEPOSIT);
    await fund.connect(user1).deposit(user1.address, token0.address, 1000);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await cc.balanceOf(user1.address)).eq(1000);

    await token0.connect(user2).approve(fund.address, WAD);
    await expect(fund.connect(user2).deposit(user1.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.connect(user1).setApprovalsFor(user2.address, APPROVED_DEPOSIT, true);
    await fund.connect(user2).deposit(user1.address, token0.address, 1000);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await token0.balanceOf(user2.address)).eq(WAD.sub(1000));
    expect(await cc.balanceOf(user1.address)).eq(2000);
    expect(await cc.balanceOf(user2.address)).eq(0);

    await fund.connect(user3).setApprovalsFor(user2.address, APPROVED_DEPOSIT, true);
    await expect(fund.connect(user2).deposit(user3.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.connect(user3).withdraw(user3.address, user3.address, token0.address, MAX_UINT); // does nothing

    await fund.connect(user1).withdraw(user1.address, user3.address, token0.address, 0);
    expect(await token0.balanceOf(user3.address)).eq(0);
    expect(await cc.balanceOf(user1.address)).eq(2000);

    await fund.connect(user1).withdraw(user1.address, user3.address, token0.address, 500);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await token0.balanceOf(user3.address)).eq(500);
    expect(await cc.balanceOf(user1.address)).eq(1500);

    await expect(fund.connect(user2).withdraw(user1.address, user3.address, token0.address, 500)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.connect(user1).setApprovalsFor(user2.address, APPROVED_WITHDRAW, true);
    await fund.connect(user2).withdraw(user1.address, user3.address, token0.address, 500);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await token0.balanceOf(user2.address)).eq(WAD.sub(1000));
    expect(await token0.balanceOf(user3.address)).eq(1000);
    expect(await cc.balanceOf(user1.address)).eq(1000);

    await fund.connect(user1).withdraw(user1.address, user1.address, token0.address, MAX_UINT);

    expect(await token0.balanceOf(user1.address)).eq(WAD);
    expect(await token0.balanceOf(user2.address)).eq(WAD.sub(1000));
    expect(await token0.balanceOf(user3.address)).eq(1000);
    expect(await cc.balanceOf(user1.address)).eq(0);
  });

  it('Invest', async () => {
    const insurer = await Factories.MockERC1363Receiver.deploy();
    await cc.ignoreAuthenticity();
    await cc.registerInsurer(insurer.address);

    await token0.connect(user1).approve(fund.address, WAD);
    await fund.connect(user1).invest(user1.address, token0.address, 1000, insurer.address);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await cc.balanceOf(user1.address)).eq(0);
    expect(await cc.balanceOf(insurer.address)).eq(1000);

    await expect(fund.connect(user1).invest(user2.address, token0.address, 1000, insurer.address)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );
    await fund.connect(user2).setAllApprovalsFor(user1.address, APPROVED_DEPOSIT);
    await expect(fund.connect(user1).invest(user2.address, token0.address, 1000, insurer.address)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );
    await fund.connect(user2).setAllApprovalsFor(user1.address, APPROVED_INVEST);
    await expect(fund.connect(user1).invest(user2.address, token0.address, 1000, insurer.address)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );
    await fund.connect(user2).setAllApprovalsFor(user1.address, APPROVED_DEPOSIT + APPROVED_INVEST);

    await fund.connect(user1).invest(user2.address, token0.address, 1000, insurer.address);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(2000));
    expect(await cc.balanceOf(user2.address)).eq(0);
    expect(await cc.balanceOf(insurer.address)).eq(2000);
  });

  it('Invest including deposit', async () => {
    const insurer = await Factories.MockERC1363Receiver.deploy();
    await cc.ignoreAuthenticity();
    await cc.registerInsurer(insurer.address);

    await token0.connect(user1).approve(fund.address, WAD);
    await fund.setSpecialRoles(user1.address, APPROVED_DEPOSIT);
    await fund.connect(user1).deposit(user1.address, token0.address, 1000);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await cc.balanceOf(user1.address)).eq(1000);

    await fund.connect(user1).investIncludingDeposit(user1.address, 200, token0.address, 1000, insurer.address);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(2000));
    expect(await cc.balanceOf(user1.address)).eq(800);
    expect(await cc.balanceOf(insurer.address)).eq(1200);

    await fund.connect(user1).investIncludingDeposit(user1.address, MAX_UINT, token0.address, 0, insurer.address);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(2000));
    expect(await cc.balanceOf(user1.address)).eq(0);
    expect(await cc.balanceOf(insurer.address)).eq(2000);
  });

  it('Trusted operations', async () => {
    await token0.connect(user1).approve(fund.address, WAD);

    await expect(fund.connect(user3).trustedDeposit(user1.address, user2.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.setSpecialRoles(user2.address, APPROVED_DEPOSIT);
    await expect(fund.connect(user3).trustedDeposit(user1.address, user2.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.setTrustedOperator(token0.address, user3.address);
    await expect(fund.connect(user3).trustedDeposit(user1.address, user2.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );

    await fund.connect(user2).setApprovalsFor(user1.address, APPROVED_DEPOSIT, true);
    await fund.connect(user3).trustedDeposit(user1.address, user2.address, token0.address, 1000);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000));
    expect(await cc.balanceOf(user1.address)).eq(0);
    expect(await cc.balanceOf(user2.address)).eq(1000);

    const insurer = await Factories.MockERC1363Receiver.deploy();
    await cc.ignoreAuthenticity();
    await cc.registerInsurer(insurer.address);

    await expect(
      fund.connect(user3).trustedInvest(user1.address, user2.address, 500, token0.address, 1000, insurer.address)
    ).revertedWith(testEnv.covReason(ProtocolErrors.AccessDenied));

    await fund.connect(user2).setApprovalsFor(user1.address, APPROVED_INVEST, true);
    await fund.connect(user3).trustedInvest(user1.address, user2.address, 500, token0.address, 1000, insurer.address);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(2000));
    expect(await cc.balanceOf(user1.address)).eq(0);
    expect(await cc.balanceOf(user2.address)).eq(500);
    expect(await cc.balanceOf(insurer.address)).eq(1500);

    await expect(
      fund.connect(user3).trustedWithdraw(user1.address, user2.address, user0.address, token0.address, 500)
    ).revertedWith(testEnv.covReason(ProtocolErrors.AccessDenied));

    await fund.connect(user2).setApprovalsFor(user1.address, APPROVED_WITHDRAW, true);
    await fund.connect(user3).trustedWithdraw(user1.address, user2.address, user0.address, token0.address, 500);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(2000));
    expect(await token0.balanceOf(user0.address)).eq(500);
    expect(await cc.balanceOf(user1.address)).eq(0);
    expect(await cc.balanceOf(user2.address)).eq(0);
    expect(await cc.balanceOf(insurer.address)).eq(1500);
  });

  it('Remove asset', async () => {
    await fund.removeAsset(zeroAddress()); // error-prone

    await token0.connect(user1).approve(fund.address, WAD);

    await fund.setSpecialRoles(user1.address, APPROVED_DEPOSIT);
    await fund.connect(user1).deposit(user1.address, token0.address, 1000);

    await fund.removeAsset(token0.address);
    await fund.removeAsset(token0.address); // error-prone for repeated calls

    await expect(fund.connect(user1).deposit(user1.address, token0.address, 1000)).revertedWith(
      testEnv.covReason('IllegalState()')
    );
    await expect(fund.connect(user1).withdraw(user1.address, user1.address, token0.address, 1000)).revertedWith(
      testEnv.covReason('IllegalState()')
    );
    await expect(fund.setPaused(token0.address, true)).revertedWith(testEnv.covReason('IllegalState()'));
  });

  it('Pause an asset', async () => {
    await token0.connect(user1).approve(fund.address, WAD);

    await fund.setSpecialRoles(user1.address, APPROVED_DEPOSIT);
    await fund.connect(user1).deposit(user1.address, token0.address, 1000);
    await fund.connect(user1).withdraw(user1.address, user1.address, token0.address, 500);

    await fund.setPaused(token0.address, true);

    const insurer = await Factories.MockERC1363Receiver.deploy();
    await cc.ignoreAuthenticity();
    await cc.registerInsurer(insurer.address);

    expect(await fund.isPaused(token0.address)).eq(true);
    await expect(fund.connect(user1).deposit(user1.address, token0.address, 1000)).revertedWith(
      testEnv.covReason(ProtocolErrors.OperationPaused)
    );
    await expect(fund.connect(user1).invest(user1.address, token0.address, 1000, insurer.address)).revertedWith(
      testEnv.covReason(ProtocolErrors.OperationPaused)
    );
    await expect(fund.connect(user1).withdraw(user1.address, user1.address, token0.address, 500)).revertedWith(
      testEnv.covReason(ProtocolErrors.OperationPaused)
    );

    await fund.setPaused(token0.address, false);
    expect(await fund.isPaused(token0.address)).eq(false);

    await fund.connect(user1).deposit(user1.address, token0.address, 1000);
    await fund.connect(user1).withdraw(user1.address, user1.address, token0.address, 500);
    await fund.connect(user1).invest(user1.address, token0.address, 1000, insurer.address);
  });

  it.skip('Price checks', async () => {
    // TODO this logic was moved to PriceRouter
    await token0.connect(user1).approve(fund.address, WAD);

    await fund.setPriceOf(token0.address, WAD.sub(WAD.div(200)));

    await fund.setSpecialRoles(user1.address, APPROVED_DEPOSIT);
    await fund.connect(user1).deposit(user1.address, token0.address, 1000000);

    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(1000000));
    expect(await cc.balanceOf(user1.address)).eq(995000);

    await fund.connect(user1).withdraw(user1.address, user1.address, token0.address, 500000);
    expect(await token0.balanceOf(user1.address)).eq(WAD.sub(500000));
    expect(await cc.balanceOf(user1.address)).eq(497500);

    await fund.setPriceOf(token0.address, WAD.div(2));

    await expect(fund.connect(user1).deposit(user1.address, token0.address, 1000000)).revertedWith(
      testEnv.covReason('ExcessiveVolatility()')
    );
    await expect(fund.connect(user1).withdraw(user1.address, user1.address, token0.address, 500000)).revertedWith(
      testEnv.covReason('ExcessiveVolatility()')
    );
  });
});
