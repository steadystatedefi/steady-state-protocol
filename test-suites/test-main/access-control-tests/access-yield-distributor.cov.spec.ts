import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, BigNumberish } from 'ethers';

import { AccessFlags } from '../../../helpers/access-flags';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, State } from './setup';

makeSuite('access: Yield Distributor', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  enum YieldSourceType {
    None,
    Passive,
  }

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    user3 = testEnv.users[3];
    state = await deployAccessControlState(deployer);

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN | AccessFlags.LP_DEPLOY);
  });

  const grantRoles = async (...roles: BigNumberish[]) => {
    let flags = BigNumber.from(0);
    for (let i = 0; i < roles.length; i++) {
      flags = flags.or(roles[i]);
    }
    await state.controller.grantRoles(deployer.address, flags);
  };

  it('Role: Borrower Admin', async () => {
    await expect(state.dist.addYieldSource(user2.address, YieldSourceType.Passive)).to.be.reverted;
    await grantRoles(AccessFlags.BORROWER_ADMIN);
    await state.dist.addYieldSource(user2.address, YieldSourceType.Passive);
    await state.dist.addYieldSource(user3.address, YieldSourceType.Passive);

    await state.dist.removeYieldSource(user2.address);
    await state.controller.revokeRoles(deployer.address, AccessFlags.BORROWER_ADMIN);
    await expect(state.dist.removeYieldSource(user3.address)).to.be.reverted;
  });

  it('Role: Collateral Currency', async () => {
    await expect(state.dist.registerStakeAsset(state.insurer.address, true)).to.be.reverted;
    await state.cc.registerInsurer(state.insurer.address);
  });

  it('Role: Liquidity Provider + Trusted Borrower', async () => {
    await grantRoles(AccessFlags.BORROWER_ADMIN);

    // The sender of the calls must be a liquidity provider
    // The account modified must be a trusted borrower
    await expect(state.dist.verifyBorrowUnderlying(user2.address, 0)).to.be.reverted;
    await expect(state.dist.verifyRepayUnderlying(user2.address, 0)).to.be.reverted;

    await state.cc.registerLiquidityProvider(deployer.address);
    await expect(state.dist.verifyBorrowUnderlying(user2.address, 0)).to.be.reverted;
    await expect(state.dist.verifyRepayUnderlying(user2.address, 0)).to.be.reverted;

    await state.dist.addYieldSource(user2.address, YieldSourceType.Passive);
    await expect(state.dist.verifyBorrowUnderlying(user2.address, 0)).to.be.reverted;
    await expect(state.dist.verifyRepayUnderlying(user2.address, 0)).to.be.reverted;

    await state.controller.grantRoles(user2.address, AccessFlags.LIQUIDITY_BORROWER);
    await state.dist.verifyBorrowUnderlying(user2.address, 0);
    await state.dist.verifyRepayUnderlying(user2.address, 0);
  });
});