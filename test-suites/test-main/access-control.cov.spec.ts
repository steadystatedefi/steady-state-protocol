import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { AccessFlags } from '../../helpers/access-flags';
import { Factories } from '../../helpers/contract-types';
import { currentTime, advanceBlock } from '../../helpers/runtime-utils';
import { IManagedAccessController, MockAccessController, MockCaller } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

// Singletons are roles that are ONLY singleton
// nonSingletons are roles that are Multilets
// protected are roles that are protectedSinglet

const multilets = {
  COLLATERAL_FUND_ADMIN: AccessFlags.COLLATERAL_FUND_ADMIN,
  PREMIUM_FUND_ADMIN: AccessFlags.PREMIUM_FUND_ADMIN,
  SWEEP_ADMIN: AccessFlags.SWEEP_ADMIN,
  PRICE_ROUTER_ADMIN: AccessFlags.PRICE_ROUTER_ADMIN,
} as const;

const protectedSinglets = {
  TREASURY: AccessFlags.TREASURY,
} as const;

const SINGLET_ONE = BigNumber.from(1).shl(30);
const SINGLET_TWO = BigNumber.from(1).shl(29);
const MULTILET_ONE = BigNumber.from(1).shl(65);

makeSuite('Access Controller', (testEnv: TestEnv) => {
  let controller: MockAccessController;
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let caller1: MockCaller;
  let caller2: MockCaller;

  before(async () => {
    admin = testEnv.users[0];
    user1 = testEnv.users[1];
    user2 = testEnv.users[2];
    controller = await Factories.MockAccessController.connectAndDeploy(admin, 'controller', [0]);
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
    await controller.grantRoles(user1.address, multilets.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user1.address, multilets.COLLATERAL_FUND_ADMIN); // Called for branch coverage
    await controller.grantRoles(user2.address, multilets.COLLATERAL_FUND_ADMIN);

    let holders = await controller.roleHolders(multilets.COLLATERAL_FUND_ADMIN);
    {
      expect(await controller.queryAccessControlMask(user1.address, 0)).eq(multilets.COLLATERAL_FUND_ADMIN);
      expect(await controller.queryAccessControlMask(user2.address, 0)).eq(multilets.COLLATERAL_FUND_ADMIN);
      expect(holders.includes(user1.address));
      expect(holders.includes(user2.address));
      expect(holders.length).eq(2);
    }

    await controller.revokeRoles(user1.address, multilets.COLLATERAL_FUND_ADMIN);
    await controller.revokeRoles(user2.address, multilets.COLLATERAL_FUND_ADMIN);
    holders = await controller.roleHolders(multilets.COLLATERAL_FUND_ADMIN);
    {
      expect(await controller.queryAccessControlMask(user1.address, 0)).eq(0);
      expect(await controller.queryAccessControlMask(user2.address, 0)).eq(0);
      expect(holders.length).eq(0);
    }

    await controller.grantRoles(user1.address, multilets.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user2.address, multilets.COLLATERAL_FUND_ADMIN);
    await controller.revokeRolesFromAll(multilets.COLLATERAL_FUND_ADMIN, 2);
    expect(await controller.queryAccessControlMask(user1.address, 0)).eq(0);
    expect(await controller.queryAccessControlMask(user2.address, 0)).eq(0);

    await controller.grantRoles(user1.address, multilets.COLLATERAL_FUND_ADMIN);
    await controller.grantRoles(user2.address, multilets.COLLATERAL_FUND_ADMIN);
    await controller.revokeRolesFromAll(multilets.COLLATERAL_FUND_ADMIN, 1);
    holders = await controller.roleHolders(multilets.COLLATERAL_FUND_ADMIN);
    expect(holders.length).eq(1);

    await controller.grantRoles(caller1.address, MULTILET_ONE);
    expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(MULTILET_ONE);
  });

  it('Add and remove singlet role', async () => {
    // Cannot set multiple singlets at once
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
    const newRole = BigNumber.from(1).shl(90);
    await controller.setAddress(newRole, caller1.address);
    holders = await controller.roleHolders(newRole);
    {
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(newRole);
      expect(await controller.isAddress(newRole, caller1.address)).eq(true);
      expect(await controller.getAddress(newRole)).eq(caller1.address);
      expect(holders[0]).eq(caller1.address);
    }
  });

  it('Preconfigured protected singlet', async () => {
    await controller.setAddress(protectedSinglets.TREASURY, caller1.address);
    // can only assign to zero state
    await expect(controller.setAddress(protectedSinglets.TREASURY, caller1.address)).to.be.reverted;

    await controller.setProtection(protectedSinglets.TREASURY, false);
    await controller.setAddress(protectedSinglets.TREASURY, caller1.address);

    const holders = await controller.roleHolders(protectedSinglets.TREASURY);
    {
      expect(await controller.queryAccessControlMask(caller1.address, 0)).eq(protectedSinglets.TREASURY);
      expect(await controller.isAddress(protectedSinglets.TREASURY, caller1.address)).eq(true);
      expect(await controller.getAddress(protectedSinglets.TREASURY)).eq(caller1.address);
      expect(holders[0]).eq(caller1.address);
    }

    await controller.setProtection(protectedSinglets.TREASURY, true);
    await expect(controller.setAddress(protectedSinglets.TREASURY, caller2.address)).to.be.reverted;
  });

  it('Protected singlet on the go', async () => {
    await controller.setAddress(SINGLET_ONE, caller1.address);
    await controller.setProtection(SINGLET_ONE, true);
    await expect(controller.setAddress(SINGLET_ONE, caller2.address)).to.be.reverted;
    await controller.setProtection(SINGLET_ONE, false);
    await controller.setAddress(SINGLET_ONE, caller2.address);
    expect(await controller.getAddress(SINGLET_ONE)).eq(caller2.address);
  });

  it('Call with roles direct', async () => {
    const role1 = multilets.PREMIUM_FUND_ADMIN;
    const role2 = multilets.SWEEP_ADMIN;
    const singletonCall = caller1.interface.encodeFunctionData('checkRoleDirect', [SINGLET_ONE]);
    const protectedCall = caller1.interface.encodeFunctionData('checkRoleDirect', [protectedSinglets.TREASURY]);
    const role1Call = caller1.interface.encodeFunctionData('checkRoleDirect', [role1]);
    const bothRolesCall = caller1.interface.encodeFunctionData('checkRoleDirect', [role1 | role2]);
    const singletonBothRolesCall = caller1.interface.encodeFunctionData('checkRoleDirect', [SINGLET_ONE.or(role1)]);

    await expect(controller.directCallWithRoles(SINGLET_ONE, caller1.address, singletonCall)).to.be.reverted;
    await expect(controller.directCallWithRoles(protectedSinglets.TREASURY, caller1.address, protectedCall)).to.be
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
    const role1 = multilets.PREMIUM_FUND_ADMIN;
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
    await expect(controller.grantAnyRoles(user1.address, multilets.PRICE_ROUTER_ADMIN)).to.be.reverted;
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
