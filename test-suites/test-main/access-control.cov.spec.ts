import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { MAX_UINT } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { currentTime, advanceBlock } from '../../helpers/runtime-utils';
import { AccessController, IManagedAccessController, MockCaller } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

// Singletons are roles that are ONLY singleton
// nonSingletons are roles that are Multilets
// protected are roles that are protectedSinglet

// roles are multilets
enum roles {
  EMERGENCY_ADMIN = 2 ** 0,
  TREASURY_ADMIN = 2 ** 1,
  COLLATERAL_FUND_ADMIN = 2 ** 2,
  INSURER_ADMIN = 2 ** 3,
  INSURER_OPS = 2 ** 4,
  PREMIUM_FUND_ADMIN = 2 ** 5,
  SWEEP_ADMIN = 2 ** 6,
  PRICE_ROUTER_ADMIN = 2 ** 7,
  UNDERWRITER_POLICY = 2 ** 8,
  UNDERWRITER_CLAIM = 2 ** 9,
}

const ROLES = MAX_UINT.mask(16);
const SINGLETS = MAX_UINT.mask(64).xor(ROLES);

const SINGLET_ONE = BigNumber.from(1).shl(30);
const SINGLET_TWO = BigNumber.from(1).shl(31);
const MULTILET_ONE = BigNumber.from(1).shl(65);

enum protectedSingletons {
  APPROVAL_CATALOG = 2 ** 16,
  TREASURY = 2 ** 17,
}

const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES);

makeSuite('Access Controller', (testEnv: TestEnv) => {
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
  });

  it('Admin roles', async () => {
    expect(await controller.isAdmin(admin.address)).eq(true);
    expect(await controller.isAdmin(user1.address)).eq(false);
    await controller.renounceTemporaryAdmin();

    // TODO: Ensure that expiry does not change in implementation
    const curTime = await currentTime();
    let expiry = curTime + 100;
    const tx = await controller.setTemporaryAdmin(user1.address, 100);
    let t = await controller.getTemporaryAdmin();
    expect(t.admin).eq(user1.address);
    expect(await controller.isAdmin(user1.address)).eq(true);
    if (tx.timestamp !== undefined) {
      expiry = tx.timestamp + 100;
      expect(t.expiresAt).eq(expiry);
    }

    await advanceBlock(expiry + 10);
    expect(await controller.isAdmin(user1.address)).eq(false);
    await controller.renounceTemporaryAdmin();
    t = await controller.getTemporaryAdmin();
    expect(t.admin).eq(zeroAddress());
    expect(t.expiresAt).eq(0);

    await controller.setTemporaryAdmin(user1.address, 100);
    expect(await controller.isAdmin(user1.address)).eq(true);
    await controller.renounceTemporaryAdmin();
    expect(await controller.isAdmin(user1.address)).eq(true);
    await controller.connect(user1).renounceTemporaryAdmin();
    expect(await controller.isAdmin(user1.address)).eq(false);

    await controller.setTemporaryAdmin(user1.address, 100);
    await controller.setTemporaryAdmin(user2.address, 100);
    expect(await controller.isAdmin(user2.address)).eq(true);
    expect(await controller.isAdmin(user1.address)).eq(false);

    await controller.setTemporaryAdmin(zeroAddress(), 100);
    expect(await controller.isAdmin(user2.address)).eq(false);
    t = await controller.getTemporaryAdmin();
    expect(t.admin).eq(zeroAddress());
    expect(t.expiresAt).eq(0);
  });

  it('Add and remove Multilet role', async () => {
    await controller.grantRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user1.address, roles.COLLATERAL_FUND_ADMIN); // Called for branch coverage
    await controller.grantRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);

    let holders = await controller.roleHolders(roles.COLLATERAL_FUND_ADMIN);
    {
      expect(await controller.queryAccessControlMask(user1.address, 0)).eq(roles.COLLATERAL_FUND_ADMIN);
      expect(await controller.queryAccessControlMask(user2.address, 0)).eq(roles.COLLATERAL_FUND_ADMIN);
      expect(holders.includes(user1.address));
      expect(holders.includes(user2.address));
      expect(holders.length).eq(2);
    }

    await controller.revokeRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.revokeRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);
    holders = await controller.roleHolders(roles.COLLATERAL_FUND_ADMIN);
    {
      expect(await controller.queryAccessControlMask(user1.address, 0)).eq(0);
      expect(await controller.queryAccessControlMask(user2.address, 0)).eq(0);
      expect(holders.length).eq(0);
    }

    await controller.grantRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.revokeRolesFromAll(roles.COLLATERAL_FUND_ADMIN, 2);
    expect(await controller.queryAccessControlMask(user1.address, 0)).eq(0);
    expect(await controller.queryAccessControlMask(user2.address, 0)).eq(0);

    await controller.grantRoles(user1.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user2.address, roles.COLLATERAL_FUND_ADMIN);
    await controller.revokeRolesFromAll(roles.COLLATERAL_FUND_ADMIN, 1);
    holders = await controller.roleHolders(roles.COLLATERAL_FUND_ADMIN);
    expect(holders.length).eq(1);

    await controller.grantRoles(caller1.address, MULTILET_ONE);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(MULTILET_ONE);
  });

  it('Add and remove singlet role', async () => {
    // Cannot add multiple roles for a singlet
    await expect(controller.setAddress(SINGLET_ONE.add(SINGLET_TWO), caller1.address)).to.be.reverted;

    await controller.setAddress(SINGLET_ONE, caller1.address);
    let holders = await controller.roleHolders(SINGLET_ONE);
    {
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(SINGLET_ONE);
      expect(await controller.isAddress(SINGLET_ONE, caller1.address)).eq(true);
      expect(await controller.isAddress(SINGLET_TWO, caller1.address)).eq(false);
      expect(await controller.getAddress(SINGLET_ONE)).eq(caller1.address);
      expect(holders[0]).eq(caller1.address);
    }

    await controller.setAddress(SINGLET_ONE, caller2.address);
    holders = await controller.roleHolders(SINGLET_ONE);
    {
      expect(await controller.queryAccessControlMask(caller2.address, 0)).eq(SINGLET_ONE);
      expect(await controller.getAddress(SINGLET_ONE)).eq(caller2.address);
      expect(await controller.isAddress(SINGLET_ONE, caller2.address)).eq(true);
      expect(holders[0]).eq(caller2.address);
      expect(await controller.isAddress(SINGLET_ONE, caller1.address)).eq(false);
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(0);
    }

    await controller.setAddress(SINGLET_ONE, zeroAddress());
    holders = await controller.roleHolders(SINGLET_ONE);
    {
      expect(await controller.queryAccessControlMask(caller2.address, 0)).eq(0);
      expect(await controller.getAddress(SINGLET_ONE)).eq(zeroAddress());
      expect(await controller.isAddress(SINGLET_ONE, caller2.address)).eq(false);
      expect(holders.length).eq(0);
    }

    await controller.setAddress(SINGLET_ONE, caller1.address);
    await controller.revokeAllRoles(caller1.address);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(0);
    expect(await controller.getAddress(SINGLET_ONE)).eq(zeroAddress());

    await controller.setAddress(SINGLET_ONE, caller1.address);
    await controller.revokeRolesFromAll(SINGLET_ONE, 10);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(0);
    expect(await controller.getAddress(SINGLET_ONE)).eq(zeroAddress());

    // Create new singlet role
    const newRole = BigNumber.from(1).shl(64);
    await controller.setAddress(newRole, caller1.address);
    holders = await controller.roleHolders(newRole);
    {
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(newRole);
      expect(await controller.isAddress(newRole, caller1.address)).eq(true);
      expect(await controller.getAddress(newRole)).eq(caller1.address);
      expect(holders[0]).eq(caller1.address);
    }
  });

  it('Protected singlet from constructor', async () => {
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
    await controller.setAddress(SINGLET_ONE, caller1.address);
    await controller.setProtection(SINGLET_ONE, true);
    await expect(controller.setAddress(SINGLET_ONE, caller2.address)).to.be.reverted;
    await controller.setProtection(SINGLET_ONE, false);
    await controller.setAddress(SINGLET_ONE, caller2.address);
    expect(await controller.getAddress(SINGLET_ONE)).eq(caller2.address);
  });

  it('Call with roles direct', async () => {
    const role1 = roles.PREMIUM_FUND_ADMIN;
    const role2 = roles.SWEEP_ADMIN;
    const singletonCall = caller1.interface.encodeFunctionData('checkRoleDirect', [SINGLET_ONE]);
    const protectedCall = caller1.interface.encodeFunctionData('checkRoleDirect', [protectedSingletons.TREASURY]);
    const role1Call = caller1.interface.encodeFunctionData('checkRoleDirect', [role1]);
    const bothRolesCall = caller1.interface.encodeFunctionData('checkRoleDirect', [role1 | role2]);
    const singletonBothRolesCall = caller1.interface.encodeFunctionData('checkRoleDirect', [SINGLET_ONE.or(role1)]);

    await expect(controller.directCallWithRoles(SINGLET_ONE, caller1.address, singletonCall)).to.be.reverted;
    await expect(controller.directCallWithRoles(protectedSingletons.TREASURY, caller1.address, protectedCall)).to.be
      .reverted;

    await controller.directCallWithRoles(role1, caller1.address, role1Call);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(0);

    await controller.grantRoles(caller1.address, role2);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(role2);
    await controller.directCallWithRoles(role1, caller1.address, bothRolesCall);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(role2);
    await controller.revokeAllRoles(caller1.address);

    await controller.setAddress(SINGLET_ONE, caller2.address);
    const params: IManagedAccessController.CallParamsStruct[] = [];
    params.push({
      accessFlags: role1,
      callAddr: caller1.address,
      callData: role1Call,
      callFlag: 0,
    });
    params.push({
      accessFlags: role1,
      callAddr: caller2.address,
      callData: singletonBothRolesCall,
      callFlag: SINGLET_ONE,
    });

    await controller.directCallWithRolesBatch(params);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(0);
    expect(await controller.queryAccessControlMask(caller2.address, 0)).eq(SINGLET_ONE);
  });

  it('Call with roles indirect', async () => {
    const role1 = roles.PREMIUM_FUND_ADMIN;
    const singletonCall = caller1.interface.encodeFunctionData('checkRoleIndirect', [controller.address, SINGLET_ONE]);
    const role1Call = caller1.interface.encodeFunctionData('checkRoleIndirect', [controller.address, role1]);

    const params: IManagedAccessController.CallParamsStruct[] = [];
    params.push({
      accessFlags: SINGLET_ONE,
      callAddr: caller1.address,
      callData: singletonCall,
      callFlag: 0,
    });
    await expect(controller.callWithRolesBatch(params)).to.be.reverted;

    params.pop();
    params.push({
      accessFlags: role1,
      callAddr: caller1.address,
      callData: role1Call,
      callFlag: 0,
    });

    await controller.callWithRolesBatch(params);
  });

  it('Grant any role', async () => {
    await expect(controller.grantAnyRoles(user1.address, roles.PRICE_ROUTER_ADMIN)).to.be.reverted;
    await controller.setAnyRoleMode(true);

    // Usually setAddress must be used for singletons
    await controller.grantAnyRoles(user1.address, SINGLET_ONE);
    await controller.grantAnyRoles(user2.address, SINGLET_ONE);

    expect(await controller.queryAccessControlMask(user1.address, 0)).eq(SINGLET_ONE);
    expect(await controller.queryAccessControlMask(user2.address, 0)).eq(SINGLET_ONE);

    await controller.setAddress(SINGLET_ONE, caller1.address);
    const holders = await controller.roleHolders(SINGLET_ONE);
    {
      expect(holders.includes(user1.address));
      expect(holders.includes(user2.address));
      expect(holders.includes(caller1.address));
      expect(holders.length).eq(3);
    }

    await controller.setAnyRoleMode(false);
    await expect(controller.grantAnyRoles(user1.address, SINGLET_TWO)).to.be.reverted;
    await expect(controller.setAnyRoleMode(true)).to.be.reverted;
  });
});
