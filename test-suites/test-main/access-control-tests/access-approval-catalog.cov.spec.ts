import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { currentTime } from '../../../helpers/runtime-utils';
import { IApprovalCatalog, InsuredPoolV1 } from '../../../types';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, State } from './setup';

makeSuite('access: Oracle Router', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;
  let user2: SignerWithAddress;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    state = await deployAccessControlState(deployer);
  });

  async function makeInsured(cid: string): Promise<InsuredPoolV1> {
    let insuredAddr = '';
    await Events.ApplicationSubmitted.waitOne(
      state.approvalCatalog.connect(deployer).submitApplication(cid, state.cc.address),
      (ev) => {
        insuredAddr = ev.insured;
      }
    );

    return Factories.InsuredPoolV1.attach(insuredAddr);
  }

  it('ROLE: Underwriter Policy', async () => {
    const cid = formatBytes32String('policy1');
    const insured: InsuredPoolV1 = await makeInsured(cid);

    const policy: IApprovalCatalog.ApprovedPolicyStruct = {
      insured: insured.address,
      requestCid: cid,
      approvalCid: cid,
      applied: false,
      policyName: 'policy 1',
      policySymbol: 'PL1',
      riskLevel: 0,
      basePremiumRate: 1,
      premiumToken: state.premToken.address,
      minPrepayValue: 1,
      rollingAdvanceWindow: 1,
      expiresAt: 2 ** 31,
    };

    {
      await expect(state.approvalCatalog.approveApplication(policy)).reverted;
      await expect(state.approvalCatalog.declineApplication(insured.address, cid, 'Because')).reverted;
      await expect(state.approvalCatalog.cancelLastPermit(insured.address)).reverted;
    }

    await state.controller.grantRoles(deployer.address, AccessFlags.UNDERWRITER_POLICY);
    {
      await state.approvalCatalog.approveApplication(policy);
      await state.approvalCatalog.declineApplication(insured.address, cid, 'Because');
      await state.approvalCatalog.cancelLastPermit(insured.address);
    }
  });

  it('ROLE: Underwriter Claim + Can claim Insurance', async () => {
    const cid = formatBytes32String('policy1');
    const claimcid = formatBytes32String('claim1');
    const insured: InsuredPoolV1 = await makeInsured(cid);

    const claim: IApprovalCatalog.ApprovedClaimStruct = {
      requestCid: claimcid,
      approvalCid: claimcid,
      payoutRatio: 0,
      since: await currentTime(),
    };

    await expect(state.approvalCatalog.connect(user2).submitClaim(insured.address, cid, 0)).reverted;
    await expect(state.approvalCatalog.cancelLastPermit(insured.address)).reverted;
    await state.approvalCatalog.submitClaim(insured.address, cid, 0);

    await expect(state.approvalCatalog.approveClaim(insured.address, claim)).reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.UNDERWRITER_CLAIM);
    await state.approvalCatalog.approveClaim(insured.address, claim);
    await state.approvalCatalog.cancelLastPermit(insured.address);
  });

  it('ROLE: Insured Admin', async () => {
    await expect(state.approvalCatalog.cancelLastPermit(user2.address)).reverted;
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURED_ADMIN);
    await state.approvalCatalog.cancelLastPermit(user2.address);
  });
});
