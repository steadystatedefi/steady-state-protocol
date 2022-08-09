import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

import { INSURER_ADMIN, TREASURY } from '../../../helpers/access-control-constants';
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

  it('ROLE: insurer admin', async () => {
    await expect(state.premiumFund.registerPremiumActuary(actuary.address, true)).to.be.reverted;
    await state.controller.grantRoles(deployer.address, INSURER_ADMIN);
    await state.premiumFund.registerPremiumActuary(actuary.address, true);
  });

  it('ROLE: Treasury', async () => {
    await expect(state.premiumFund.collectFees([user2.address], 1, deployer.address)).to.be.reverted;
    await state.controller.grantAnyRoles(deployer.address, TREASURY);
    await state.premiumFund.collectFees([user2.address], 1, deployer.address);
  });
});
