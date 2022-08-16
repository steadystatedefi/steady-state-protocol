import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

import { INSURER_ADMIN, LP_DEPLOY } from '../../../helpers/access-control-constants';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, State } from './setup';

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
  });

  it('ROLE: LP Deploy', async () => {
    await expect(state.cc.registerLiquidityProvider(user2.address)).to.be.reverted;
    await expect(state.cc.unregister(user2.address)).to.be.reverted;

    await state.controller.grantRoles(deployer.address, LP_DEPLOY);
    await state.cc.registerLiquidityProvider(user2.address);
    await state.cc.unregister(user2.address);
    await state.cc.connect(user2).unregister(user2.address);
  });

  it('ROLE: Insurer Admin', async () => {
    await expect(state.cc.registerInsurer(user2.address)).to.be.reverted;
    await expect(state.cc.unregister(user2.address)).to.be.reverted;

    await state.controller.grantRoles(deployer.address, INSURER_ADMIN);
    await state.cc.registerInsurer(user2.address);
    await state.cc.unregister(user2.address);
    await expect(state.cc.unregister(user2.address)).to.be.reverted;
  });

  it('ROLE: mint and burn', async () => {
    await state.controller.grantRoles(deployer.address, LP_DEPLOY);
    await expect(state.cc.mint(user2.address, 100)).to.be.reverted;
    await expect(state.cc.mintAndTransfer(user2.address, user3.address, 0, 0)).to.be.reverted;
    await expect(state.cc.burn(user2.address, 100)).to.be.reverted;

    await state.cc.registerLiquidityProvider(deployer.address);
    await state.cc.mint(user2.address, 100);
    await state.cc.mintAndTransfer(user2.address, user3.address, 0, 0);
    await state.cc.burn(user2.address, 100);
  });

  it('ROLE: Borrow Manager', async () => {
    await expect(state.cc.connect(user2).transferOnBehalf(user2.address, user3.address, 0)).to.be.reverted;

    await state.cc.setBorrowManager(user2.address);
    await state.cc.connect(user2).transferOnBehalf(user2.address, user3.address, 0);

    // Only ACL admin can set borrow manager
    await expect(state.cc.connect(user2).setBorrowManager(user2.address)).to.be.reverted;
  });
});
