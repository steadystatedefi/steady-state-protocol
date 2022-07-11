import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress, zeros } from 'ethereumjs-util';
import { BigNumber } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { MAX_UINT } from '../../helpers/constants';
import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import { currentTime } from '../../helpers/runtime-utils';
import {
  AccessController,
  ProxyCatalog,
  ApprovalCatalogV1,
  InsuredPoolV1,
  MockERC20,
  ApprovalCatalog,
  IApprovalCatalog,
} from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

const UNDERWRITER_POLICY = BigNumber.from(1).shl(8);
const UNDERWRITER_CLAIM = BigNumber.from(1).shl(9);
const PROXY_FACTORY = BigNumber.from(1).shl(26);
const APPROVAL_CATALOG = BigNumber.from(1).shl(16);

const ROLES = MAX_UINT.mask(16);
const SINGLETS = MAX_UINT.mask(64).xor(ROLES);
const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES).xor(APPROVAL_CATALOG);

const ZERO_BYTES = formatBytes32String('');

makeSuite.only('Approval Catalog', (testEnv: TestEnv) => {
  let controller: AccessController;
  let proxyCatalog: ProxyCatalog;
  let approvalCatalog: ApprovalCatalogV1;
  let insuredV1: InsuredPoolV1;
  let cc: MockERC20;
  let premiumToken: MockERC20;
  let user1: SignerWithAddress;

  const proxyType = formatBytes32String('INSURED_POOL');

  const submitApplication = async (cid: string) => {
    let addr = '';
    await Events.ApplicationSubmitted.waitOne(approvalCatalog['submitApplication(bytes32)'](cid), (ev) => {
      addr = ev.insured;
      expect(ev.requestCid).eq(cid);
    });
    return addr;
  };

  before(async () => {
    user1 = testEnv.users[1];
    controller = await Factories.AccessController.deploy(SINGLETS, ROLES, PROTECTED_SINGLETS);
    proxyCatalog = await Factories.ProxyCatalog.deploy(controller.address);
    approvalCatalog = await Factories.ApprovalCatalogV1.deploy(controller.address);
    cc = await Factories.MockERC20.deploy('Collateral Currency', 'CC', 18);
    premiumToken = await Factories.MockERC20.deploy('Premium Token', 'PRM', 18);
    insuredV1 = await Factories.InsuredPoolV1.deploy(controller.address, cc.address);

    await controller.setAddress(PROXY_FACTORY, proxyCatalog.address);
    await controller.setAddress(APPROVAL_CATALOG, approvalCatalog.address);
    await controller.grantRoles(user1.address, UNDERWRITER_POLICY);
    await controller.grantRoles(user1.address, UNDERWRITER_CLAIM);
    await proxyCatalog.addAuthenticImplementation(insuredV1.address, proxyType);
    await proxyCatalog.setDefaultImplementation(insuredV1.address);
  });

  it('Submit an application', async () => {
    let cid = formatBytes32String('policy1');
    let insuredAddr = await submitApplication(cid);
    expect(await proxyCatalog.getProxyImplementation(insuredAddr)).eq(insuredV1.address);
    expect(await approvalCatalog.hasApprovedApplication(insuredAddr)).eq(false);
    await expect(approvalCatalog.getApprovedApplication(insuredAddr)).to.be.reverted;

    const insuredV2 = await Factories.InsuredPoolV2.deploy(controller.address, cc.address);
    await proxyCatalog.addAuthenticImplementation(insuredV2.address, proxyType);

    cid = formatBytes32String('policy2');
    await Events.ApplicationSubmitted.waitOne(
      approvalCatalog['submitApplication(bytes32,address)'](cid, insuredV2.address),
      (ev) => {
        insuredAddr = ev.insured;
        expect(ev.requestCid).eq(cid);
      }
    );
    expect(await approvalCatalog.hasApprovedApplication(insuredAddr)).eq(false);
    expect(await proxyCatalog.getProxyImplementation(insuredAddr)).eq(insuredV2.address);
    await Events.ApplicationSubmitted.waitOne(approvalCatalog.resubmitApplication(insuredAddr, cid), (ev) => {
      expect(ev.insured).eq(insuredAddr);
      expect(ev.requestCid).eq(cid);
    });
  });

  it('Approve an application', async () => {
    const cid = formatBytes32String('policy1');
    const insuredAddr = await submitApplication(cid);
    const user1Catalog = approvalCatalog.connect(user1);

    const policy: IApprovalCatalog.ApprovedPolicyStruct = {
      insured: insuredAddr,
      requestCid: cid,
      approvalCid: cid,
      applied: false,
      policyName: 'policy 1',
      policySymbol: 'PL1',
      riskLevel: 1,
      basePremiumRate: 1,
      premiumToken: premiumToken.address,
      minPrepayValue: 1,
      rollingAdvanceWindow: 1,
      expiresAt: (await currentTime()) + 100000,
    };

    await expect(approvalCatalog.approveApplication(policy)).to.be.reverted;

    policy.insured = zeroAddress();
    await expect(user1Catalog.approveApplication(policy)).to.be.reverted;
    policy.insured = insuredAddr;
    policy.requestCid = formatBytes32String('');
    await expect(user1Catalog.approveApplication(policy)).to.be.reverted;
    policy.requestCid = cid;
    policy.applied = true;
    await expect(user1Catalog.approveApplication(policy)).to.be.reverted;
    policy.applied = false;

    await user1Catalog.approveApplication(policy);
    expect(await approvalCatalog.hasApprovedApplication(insuredAddr)).eq(true);

    // await expect(approvalCatalog['submitApplication(bytes32)'](cid)).to.be.reverted;
    await expect(approvalCatalog.resubmitApplication(insuredAddr, cid)).to.be.reverted;
    await approvalCatalog.getApprovedApplication(insuredAddr);
    const res = await approvalCatalog.getAppliedApplicationForInsurer(insuredAddr);
    expect(res.valid).eq(false);
  });

  it('Apply an application', async () => {
    const cid = formatBytes32String('policy1');
    const insuredAddr = await submitApplication(cid);

    const policy: IApprovalCatalog.ApprovedPolicyStruct = {
      insured: insuredAddr,
      requestCid: cid,
      approvalCid: cid,
      applied: false,
      policyName: 'policy 1',
      policySymbol: 'PL1',
      riskLevel: 1,
      basePremiumRate: 1,
      premiumToken: premiumToken.address,
      minPrepayValue: 1,
      rollingAdvanceWindow: 1,
      expiresAt: (await currentTime()) + 100000,
    };
    await approvalCatalog.connect(user1).approveApplication(policy);

    const insured = Factories.InsuredPoolV1.attach(insuredAddr);

    await expect(insured.connect(user1).applyApprovedApplication()).to.be.reverted;
    await insured.applyApprovedApplication();

    const res = await approvalCatalog.getAppliedApplicationForInsurer(insuredAddr);
    expect(res.valid).eq(true);
    expect(res.data.premiumToken).eq(policy.premiumToken);
    expect(res.data.basePremiumRate).eq(policy.basePremiumRate);
    expect(res.data.riskLevel).eq(policy.riskLevel);
  });

  it('Decline applications', async () => {
    const cid = formatBytes32String('policy1');
    const insuredAddr = await submitApplication(cid);
    const user1Catalog = approvalCatalog.connect(user1);
    const policy: IApprovalCatalog.ApprovedPolicyStruct = {
      insured: insuredAddr,
      requestCid: cid,
      approvalCid: cid,
      applied: false,
      policyName: 'policy 1',
      policySymbol: 'PL1',
      riskLevel: 1,
      basePremiumRate: 1,
      premiumToken: premiumToken.address,
      minPrepayValue: 1,
      rollingAdvanceWindow: 1,
      expiresAt: (await currentTime()) + 100000,
    };

    await expect(user1Catalog.declineApplication(zeroAddress(), cid, 'Decline reason')).to.be.reverted;
    await user1Catalog.approveApplication(policy);
    expect(await approvalCatalog.hasApprovedApplication(insuredAddr)).eq(true);
    await user1Catalog.declineApplication(insuredAddr, cid, 'Decline reason');
    expect(await approvalCatalog.hasApprovedApplication(insuredAddr)).eq(false);
  });
});
