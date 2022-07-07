import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { Factories } from '../../helpers/contract-types';
import { currentTime, advanceBlock } from '../../helpers/runtime-utils';
import { AccessController, MockCaller } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

// Singletons are roles that are ONLY singleton
// nonSingletons are roles that are Multilets
// protected are roles that are protectedSinglet
enum roles {
  EMERGENCY_ADMIN = 2 ** 0,
  TREASURY_ADMIN = 2 ** 1,
  COLLATERAL_FUND_ADMIN = 2 ** 2,
  INSURER_ADMIN = 2 ** 3,
  INSURER_OPS = 2 ** 4,
  PREMIUM_FUND_ADMIN = 2 ** 5,
  SWEEP_ADMIN = 2 ** 6,
  ORACLE_ADMIN = 2 ** 7,
  UNDERWRITER_POLICY = 2 ** 8,
  UNDERWRITER_CLAIM = 2 ** 9,
}

const ROLES = BigNumber.from(1).shl(16).sub(1);
const NOT_ROLES = BigNumber.from('115792089237316195423570985008687907853269984665640564039457584007913129574400');
const SINGLETS = BigNumber.from(1).shl(64).sub(1).and(NOT_ROLES);

const TEST_ONE = BigNumber.from(1).shl(30);
const TEST_TWO = BigNumber.from(1).shl(31);

enum protectedSingletons {
  APPROVAL_CATALOG = 2 ** 16,
  TREASURY = 2 ** 17,
}

const PROTECTED_SINGLETS = BigNumber.from(1).shl(26).sub(1).and(NOT_ROLES);

makeSuite.only('Access Controller', (testEnv: TestEnv) => {
  let controller: AccessController;
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let caller1: MockCaller;
  let caller2: MockCaller;

  before(async () => {
    admin = testEnv.users[0];
    user1 = testEnv.users[1];
    user2 = testEnv.users[2];
    controller = await Factories.AccessController.connectAndDeploy(admin, 'controller', [
      SINGLETS,
      ROLES,
      PROTECTED_SINGLETS,
    ]);
    caller1 = await Factories.MockCaller.deploy();
    caller2 = await Factories.MockCaller.deploy();

    console.log('singlets', SINGLETS.toHexString());
    console.log('roles', ROLES.toHexString());
    console.log('protected', PROTECTED_SINGLETS.toHexString());
  });

  it('Admin roles', async () => {
    expect(await controller.isAdmin(admin.address)).eq(true);
    expect(await controller.isAdmin(user1.address)).eq(false);
    await controller.renounceTemporaryAdmin();

    // TODO: Ensure that expiry does not change in implementation
    const curTime = await currentTime();
    const expiry = curTime + 100;
    await controller.setTemporaryAdmin(user1.address, 100);
    const t = await controller.getTemporaryAdmin();
    expect(t.admin).eq(user1.address);
    expect(await controller.isAdmin(user1.address)).eq(true);
    // expect(t.expiresAt).eq(expiry);

    await advanceBlock(expiry + 10);
    expect(await controller.isAdmin(user1.address)).eq(false);
    await controller.renounceTemporaryAdmin();

    await controller.setTemporaryAdmin(user1.address, 100);
    expect(await controller.isAdmin(user1.address)).eq(true);
    await controller.renounceTemporaryAdmin();
    expect(await controller.isAdmin(user1.address)).eq(true);
    await controller.connect(user1).renounceTemporaryAdmin();
    expect(await controller.isAdmin(user1.address)).eq(false);
  });

  it('Add and remove Multilet role', async () => {
    await controller.grantRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);
    expect(await controller.queryAccessControlMask(user1.address, 0)).eq(roles.COLLATERAL_FUND_ADMIN);
    expect(await controller.queryAccessControlMask(user2.address, 0)).eq(roles.COLLATERAL_FUND_ADMIN);

    await controller.revokeRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.revokeRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);
    expect(await controller.queryAccessControlMask(user1.address, 0)).eq(0);
    expect(await controller.queryAccessControlMask(user2.address, 0)).eq(0);

    await controller.grantRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);
    const holders = await controller.roleHolders(roles.COLLATERAL_FUND_ADMIN);
    expect(holders.includes(user1.address));
    expect(holders.includes(user2.address));

    await controller.revokeRolesFromAll(roles.COLLATERAL_FUND_ADMIN, 2);
    expect(await controller.queryAccessControlMask(user1.address, 0)).eq(0);
    expect(await controller.queryAccessControlMask(user2.address, 0)).eq(0);
  });

  it('Add and remove singlet role', async () => {
    // Cannot add multiple roles for a singlet
    await expect(controller.setAddress(TEST_ONE.add(TEST_TWO), caller1.address)).to.be.reverted;

    await controller.setAddress(TEST_ONE, caller1.address);
    let holders = await controller.roleHolders(TEST_ONE);
    {
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(TEST_ONE);
      expect(await controller.isAddress(TEST_ONE, caller1.address)).eq(true);
      expect(await controller.isAddress(TEST_TWO, caller1.address)).eq(false);
      expect(await controller.getAddress(TEST_ONE)).eq(caller1.address);
      expect(holders[0]).eq(caller1.address);
    }

    await controller.setAddress(TEST_ONE, caller2.address);
    holders = await controller.roleHolders(TEST_ONE);
    {
      expect(await controller.queryAccessControlMask(caller2.address, 0)).eq(TEST_ONE);
      expect(await controller.getAddress(TEST_ONE)).eq(caller2.address);
      expect(await controller.isAddress(TEST_ONE, caller2.address)).eq(true);
      expect(holders[0]).eq(caller2.address);
      expect(await controller.isAddress(TEST_ONE, caller1.address)).eq(false);
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(0);
    }

    await controller.setAddress(TEST_ONE, zeroAddress());
    holders = await controller.roleHolders(TEST_ONE);
    {
      expect(await controller.queryAccessControlMask(caller2.address, 0)).eq(0);
      expect(await controller.getAddress(TEST_ONE)).eq(zeroAddress());
      expect(await controller.isAddress(TEST_ONE, caller2.address)).eq(false);
      expect(holders.length).eq(0);
    }
  });

  it('Protected singlet from construactor', async () => {
    await expect(controller.setAddress(protectedSingletons.TREASURY, caller1.address)).to.be.reverted;
    await controller.setProtection(protectedSingletons.TREASURY, false);
    await controller.setAddress(protectedSingletons.TREASURY, caller1.address);
    const holders = await controller.roleHolders(protectedSingletons.TREASURY);
    {
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(protectedSingletons.TREASURY);
      expect(await controller.isAddress(protectedSingletons.TREASURY, caller1.address)).eq(true);
      expect(await controller.getAddress(protectedSingletons.TREASURY)).eq(caller1.address);
      expect(holders[0]).eq(caller1.address);
    }

    await controller.setProtection(protectedSingletons.TREASURY, true);
    await expect(controller.setAddress(protectedSingletons.TREASURY, caller2.address)).to.be.reverted;
  });

  it('Protected singlet from regular singlet', async () => {
    await controller.setAddress(TEST_ONE, caller1.address);
    await controller.setProtection(TEST_ONE, true);
    await expect(controller.setAddress(TEST_ONE, caller2.address)).to.be.reverted;
    await controller.setProtection(TEST_ONE, false);
    await controller.setAddress(TEST_ONE, caller2.address);
    expect(await controller.getAddress(TEST_ONE)).eq(caller2.address);
  });

  /*
  it('Call with Roles', async() => {

  });

  it('Grant any role', async() => {

  });
  */
});
