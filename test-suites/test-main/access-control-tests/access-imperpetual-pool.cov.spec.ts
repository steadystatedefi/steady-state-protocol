import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { MAX_UINT } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { IApprovalCatalog, ImperpetualPoolExtension } from '../../../types';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, setInsurer, State } from './setup';

makeSuite('access: Imperpetual Pool', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  let ext: ImperpetualPoolExtension;

  const params: WeightedPoolParamsStruct = {
    maxAdvanceUnits: 100_000_000,
    minAdvanceUnits: 1_000,
    riskWeightTarget: 10_00,
    minInsuredSharePct: 1_00,
    maxInsuredSharePct: 100_00,
    minUnitsPerRound: 10,
    maxUnitsPerRound: 20,
    overUnitsPerRound: 30,
    coveragePrepayPct: 100_00,
    maxUserDrawdownPct: 0,
    unitsPerAutoPull: 0,
  };

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    user3 = testEnv.users[3];
    state = await deployAccessControlState(deployer);

    await setInsurer(state, deployer, user2.address);
    ext = Factories.ImperpetualPoolExtension.attach(state.insurer.address);

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN | AccessFlags.LP_DEPLOY);
    await state.cc.registerInsurer(state.insurer.address);
    await state.controller.revokeRoles(deployer.address, AccessFlags.INSURER_ADMIN);
  });

  it('ROLE: Governor', async () => {
    await state.insured.joinPool(state.insurer.address);
    await expect(state.insurer.approveJoiner(state.insured.address, true)).to.be.reverted;
    await expect(state.insurer.setPoolParams(params)).to.be.reverted;

    await state.insurer.connect(user2).approveJoiner(state.insured.address, true);
    await state.insurer.connect(user2).setPoolParams(params);
  });

  it('ROLE: Insurer Ops', async () => {
    await state.insured.joinPool(state.insurer.address);

    await expect(state.insurer.approveJoiner(state.insured.address, true)).reverted;
    await expect(state.insurer.addSubrogation(user2.address, 0)).reverted;
    await expect(ext.cancelCoverageDemand(state.insured.address, 0, MAX_UINT)).reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_OPS);
    await state.insurer.approveJoiner(state.insured.address, true);
    await state.insurer.addSubrogation(user2.address, 0);

    await state.insured.pushCoverageDemandTo([state.insurer.address], [11]);

    await state.controller.revokeRoles(deployer.address, AccessFlags.INSURER_OPS);
    await expect(ext.cancelCoverageDemand(state.insured.address, 1, MAX_UINT)).reverted;
    await expect(ext.cancelCoverage(state.insured.address, 0)).reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_OPS);
    await ext.cancelCoverageDemand(state.insured.address, 1, MAX_UINT);
    await ext.cancelCoverage(state.insured.address, 0);
  });

  it('ROLE: Insurer Admin', async () => {
    await expect(state.insurer.connect(user3).setGovernor(user3.address)).to.be.reverted;
    await expect(state.insurer.connect(user3).setPremiumDistributor(user3.address)).to.be.reverted;
    await expect(state.insurer.connect(user3).setPoolParams(params)).to.be.reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.insurer.setGovernor(user3.address);
    await state.insurer.setPremiumDistributor(user3.address);
    await state.insurer.setPoolParams(params);
  });

  it('ROLE: Collateral Currency', async () => {
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.cc.registerLiquidityProvider(deployer.address);

    await expect(state.insurer.onTransferReceived(user2.address, user2.address, 100, '')).to.be.reverted;
    await state.cc.mintAndTransfer(user2.address, user2.address, 100, 100);
  });

  it('ROLE: onlySelf', async () => {
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_OPS);
    await state.insured.joinPool(state.insurer.address);
    await state.insurer.approveJoiner(state.insured.address, true);

    await expect(state.insurer.updateCoverageOnCancel(state.insured.address, 0, 0, 0, 0)).reverted;
    await expect(state.insurer.updateCoverageOnReconcile(state.insured.address, 0, 0)).reverted;

    await state.insured.reconcileWithInsurers(0, 0);
    await ext.cancelCoverage(state.insured.address, 0);
  });

  it('ROLE: onlyActiveInsureds', async () => {
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_OPS | AccessFlags.INSURED_OPS);
    await state.insured.joinPool(state.insurer.address);

    await state.controller.revokeAllRoles(deployer.address);
    {
      await expect(state.insured.pushCoverageDemandTo([state.insurer.address], [11])).reverted;
      await expect(ext.cancelCoverageDemand(state.insured.address, 1, MAX_UINT)).reverted;
      await expect(ext.receiveDemandedCoverage(state.insured.address, MAX_UINT)).reverted;
      await expect(ext.cancelCoverage(state.insured.address, 0)).reverted;
    }

    const claim: IApprovalCatalog.ApprovedClaimStruct = {
      requestCid: formatBytes32String('claim1'),
      approvalCid: formatBytes32String('claim2'),
      payoutRatio: 0,
      since: 2 ** 30,
    };
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_OPS | AccessFlags.UNDERWRITER_CLAIM);
    await state.approvalCatalog.submitClaim(state.insured.address, formatBytes32String('claim1'), 0);
    await state.approvalCatalog.approveClaim(state.insured.address, claim);

    await state.insurer.approveJoiner(state.insured.address, true);
    await state.insured.pushCoverageDemandTo([state.insurer.address], [11]);
    await ext.cancelCoverageDemand(state.insured.address, 1, MAX_UINT);
    await state.insured.reconcileWithInsurers(0, 0);
    await state.insured.cancelCoverage(user2.address, 0);
  });

  it('ROLE: onlyPremiumDistributor', async () => {
    await state.controller.grantRoles(
      deployer.address,
      AccessFlags.INSURER_ADMIN | AccessFlags.INSURER_OPS | AccessFlags.INSURED_OPS
    );
    await state.insured.joinPool(state.insurer.address);

    await expect(state.insurer.burnPremium(user2.address, 0, user3.address)).reverted;
    await expect(state.insurer.collectDrawdownPremium()).reverted;

    await state.insurer.setPremiumDistributor(user2.address);
    await state.insurer.connect(user2).burnPremium(user2.address, 0, user3.address);
    await state.insurer.connect(user2).collectDrawdownPremium();
  });
});
