import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { MockPremiumActuary } from '../../../types';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, State } from './setup';

makeSuite('access: Premium Fund', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;

  let actuary: MockPremiumActuary;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    state = await deployAccessControlState(deployer);

    actuary = await Factories.MockPremiumActuary.deploy(state.premiumFund.address, state.cc.address);
  });

  it('ROLE: Insurer Admin', async () => {
    await expect(state.premiumFund.registerPremiumActuary(actuary.address, true)).to.be.reverted;
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.premiumFund.registerPremiumActuary(actuary.address, true);
  });

  it('ROLE: Treasury', async () => {
    await expect(state.premiumFund.collectFees([user2.address], 1, deployer.address)).to.be.reverted;
    await state.controller.grantAnyRoles(deployer.address, AccessFlags.TREASURY);
    await state.premiumFund.collectFees([user2.address], 1, deployer.address);
  });

  it('ROLE: Emergency Admin', async () => {
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.premiumFund.registerPremiumActuary(actuary.address, true);
    await expect(state.premiumFund.setPaused(actuary.address, state.premToken.address, true)).reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.EMERGENCY_ADMIN);
    await state.premiumFund.setPaused(actuary.address, state.premToken.address, true);
  });
});
