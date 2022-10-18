import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

import { AccessFlags } from '../../../helpers/access-flags';
import { ProtocolErrors } from '../../../helpers/contract-errors';
import { MockMinter } from '../../../types';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, setInsurer, State, makeMockMinter } from './setup';

makeSuite('access: Collateral Currency', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    user3 = testEnv.users[3];
    state = await deployAccessControlState(deployer);
    await setInsurer(state, deployer, deployer.address);
  });

  it('ROLE: LP Deploy', async () => {
    await expect(state.cc.registerLiquidityProvider(state.fund.address)).to.be.reverted;
    await expect(state.cc.unregister(state.fund.address)).to.be.reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.LP_DEPLOY);
    await state.cc.registerLiquidityProvider(state.fund.address);
    await state.cc.unregister(state.fund.address);
    // await state.cc.connect(user2).unregister(user2.address); // cannot test without fund implementing unregister
  });

  it('ROLE: Insurer Admin', async () => {
    await expect(state.cc.registerInsurer(state.insurer.address)).to.be.reverted;
    await expect(state.cc.unregister(state.insurer.address)).to.be.reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.cc.registerInsurer(state.insurer.address);
    await state.cc.unregister(state.insurer.address);
    await expect(state.cc.unregister(state.insurer.address)).to.be.reverted;
  });

  it('ROLE: mint and burn', async () => {
    const minter: MockMinter = await makeMockMinter(state, deployer);

    await state.controller.grantRoles(deployer.address, AccessFlags.LP_DEPLOY);
    await expect(minter.mint(user2.address, 100)).reverted;
    await expect(minter.mintAndTransfer(user2.address, user3.address, 0, 0)).reverted;
    await expect(minter.mintAndTransfer(user2.address, user2.address, 0, 0)).reverted;
    await expect(minter.burn(user2.address, 100)).reverted;

    await state.cc.registerLiquidityProvider(minter.address);
    await minter.mint(user2.address, 100);
    await minter.burn(user2.address, 100);

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.cc.registerInsurer(state.insurer.address);
    await minter.mintAndTransfer(user2.address, state.insurer.address, 300, 0);
    expect(await state.cc.balanceOf(state.insurer.address)).eq(300);
    await expect(minter.burn(state.insurer.address, 300)).revertedWith(
      testEnv.covReason(ProtocolErrors.BalanceOperationRestricted)
    );
  });

  it('ROLE: Borrow Manager', async () => {
    await expect(state.cc.connect(user2).transferOnBehalf(user2.address, user3.address, 0)).to.be.reverted;

    await state.cc.setBorrowManager(user2.address);
    await state.cc.connect(user2).transferOnBehalf(user2.address, user3.address, 0);

    // Only ACL admin can set borrow manager
    await expect(state.cc.connect(user2).setBorrowManager(user2.address)).to.be.reverted;
  });
});
