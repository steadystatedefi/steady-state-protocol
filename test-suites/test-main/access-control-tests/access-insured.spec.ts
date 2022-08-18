import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { formatBytes32String } from 'ethers/lib/utils';

import { INSURER_ADMIN, TREASURY } from '../../../helpers/access-control-constants';
import { AccessFlags } from '../../../helpers/access-flags';
import { WAD } from '../../../helpers/constants';
import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { currentTime } from '../../../helpers/runtime-utils';
import { IApprovalCatalog, InsuredPoolV1 } from '../../../types';
import { InsuredParamsStruct } from '../../../types/contracts/insured/InsuredJoinBase';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, setInsurer, State } from './setup';

makeSuite('access: Insured', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    state = await deployAccessControlState(deployer);
    await setInsurer(state, deployer, deployer.address);
  });

  async function makeInsured(user: SignerWithAddress, c: string): Promise<string> {
    let insured = '';
    await Events.ApplicationSubmitted.waitOne(
      state.approvalCatalog.connect(user).submitApplication(c, state.cc.address),
      (ev) => {
        insured = ev.insured;
      }
    );
    await state.premToken.mint(insured, WAD);
    return insured;
  }

  it('ROLE: Governor', async () => {
    await state.controller.grantAnyRoles(
      deployer.address,
      AccessFlags.UNDERWRITER_POLICY | AccessFlags.INSURER_OPS | AccessFlags.UNDERWRITER_CLAIM
    );
    const cid = formatBytes32String('approval1');
    const claimcid = formatBytes32String('claim1');
    const insured = Factories.InsuredPoolV1.attach(await makeInsured(user2, cid));
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
    const params: InsuredParamsStruct = {
      minPerInsurer: 0,
    };
    const claim: IApprovalCatalog.ApprovedClaimStruct = {
      requestCid: claimcid,
      approvalCid: claimcid,
      payoutRatio: 0,
      since: await currentTime(),
    };

    await state.approvalCatalog.approveApplication(policy);

    {
      await expect(insured.applyApprovedApplication()).reverted;
      await expect(insured.joinPool(state.insurer.address)).reverted;
      await expect(state.approvalCatalog.submitClaim(insured.address, claimcid, 0)).reverted;
    }

    await insured.connect(user2).joinPool(state.insurer.address);
    await state.insurer.approveJoiner(insured.address, true);
    await state.approvalCatalog.connect(user2).submitClaim(insured.address, claimcid, 0);
    await state.approvalCatalog.approveClaim(insured.address, claim);

    {
      await expect(insured.pushCoverageDemandTo([state.insurer.address], [10])).reverted;
      await expect(insured.setInsuredParams(params)).reverted;
      await expect(insured.reconcileWithInsurers(0, 0)).reverted;
      await expect(insured.cancelCoverage(user2.address, 0)).reverted;
      await expect(insured.withdrawPrepay(user2.address, 0)).reverted;
      await expect(insured.setGovernor(deployer.address)).reverted;
    }

    {
      await insured.connect(user2).pushCoverageDemandTo([state.insurer.address], [10]);
      await insured.connect(user2).setInsuredParams(params);
      await insured.connect(user2).reconcileWithInsurers(0, 0);
      await insured.connect(user2).cancelCoverage(user2.address, 0);
      await insured.connect(user2).withdrawPrepay(user2.address, 0);
      await insured.connect(user2).setGovernor(deployer.address);
    }
  });

  it('ROLE: Insured Ops', async () => {
    await state.controller.grantAnyRoles(
      deployer.address,
      AccessFlags.UNDERWRITER_POLICY | AccessFlags.INSURER_OPS | AccessFlags.UNDERWRITER_CLAIM
    );
    const cid = formatBytes32String('approval1');
    const claimcid = formatBytes32String('claim1');
    const insured = Factories.InsuredPoolV1.attach(await makeInsured(user2, cid));
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
    const params: InsuredParamsStruct = {
      minPerInsurer: 0,
    };
    const claim: IApprovalCatalog.ApprovedClaimStruct = {
      requestCid: claimcid,
      approvalCid: claimcid,
      payoutRatio: 0,
      since: await currentTime(),
    };

    await state.approvalCatalog.approveApplication(policy);
    await insured.connect(user2).joinPool(state.insurer.address);
    await state.insurer.approveJoiner(insured.address, true);
    await state.approvalCatalog.connect(user2).submitClaim(insured.address, claimcid, 0);
    await state.approvalCatalog.approveClaim(insured.address, claim);

    {
      await expect(insured.pushCoverageDemandTo([state.insurer.address], [10])).reverted;
      await expect(insured.setInsuredParams(params)).reverted;
      await expect(insured.reconcileWithInsurers(0, 0)).reverted;
      await expect(insured.cancelCoverage(user2.address, 0)).reverted;
    }

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURED_OPS);

    {
      await insured.pushCoverageDemandTo([state.insurer.address], [10]);
      await insured.setInsuredParams(params);
      await insured.reconcileWithInsurers(0, 0);
      await insured.cancelCoverage(user2.address, 0);
    }
  });

  it('ROLE: Insured Admin', async () => {
    const cid = formatBytes32String('approval1');
    const insured = Factories.InsuredPoolV1.attach(await makeInsured(user2, cid));

    await expect(insured.setGovernor(deployer.address)).reverted;
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURED_ADMIN);
    await insured.setGovernor(deployer.address);
  });
});
