import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { MAX_UINT, WAD } from '../../../helpers/constants';
import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import {
  AccessController,
  ApprovalCatalog,
  CollateralCurrency,
  CollateralFundV1,
  IApprovalCatalog,
  ImperpetualPoolV1,
  InsuredPoolV1,
  MockERC20,
  OracleRouterV1,
  PremiumFundV1,
  ProxyCatalog,
  YieldDistributorV1,
} from '../../../types';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';

const insurerImplName = formatBytes32String('IMPERPETUAL_INDEX_POOL');
const insuredImplName = formatBytes32String('INSURED_POOL');

export type State = {
  controller: AccessController;
  proxyCatalog: ProxyCatalog;
  approvalCatalog: ApprovalCatalog;
  cc: CollateralCurrency;
  fund: CollateralFundV1;
  oracle: OracleRouterV1;
  premiumFund: PremiumFundV1;
  dist: YieldDistributorV1;

  insured: InsuredPoolV1;
  insurer: ImperpetualPoolV1;
  premToken: MockERC20;

  fundFuses: BigNumberish;
};

// The returned state's insurerv1 is *not* initialized and must be
export async function deployAccessControlState(deployer: SignerWithAddress): Promise<State> {
  const state: State = {} as State;
  state.fundFuses = 2;
  state.controller = await Factories.AccessController.connectAndDeploy(deployer, 'controller', [0]);
  state.proxyCatalog = await Factories.ProxyCatalog.connectAndDeploy(deployer, 'proxyCatalog', [
    state.controller.address,
  ]);
  state.approvalCatalog = await Factories.ApprovalCatalogV1.connectAndDeploy(deployer, 'approvalCatalog', [
    state.controller.address,
  ]);
  state.cc = await Factories.CollateralCurrency.connectAndDeploy(deployer, 'cc', [
    state.controller.address,
    'Collateral Currency',
    'CC',
    18,
  ]);
  state.fund = await Factories.CollateralFundV1.connectAndDeploy(deployer, 'fund', [
    state.controller.address,
    state.cc.address,
    state.fundFuses,
  ]);
  state.oracle = await Factories.OracleRouterV1.connectAndDeploy(deployer, 'oracle', [
    state.controller.address,
    state.cc.address,
  ]);
  state.premiumFund = await Factories.PremiumFundV1.connectAndDeploy(deployer, 'premiumFund', [
    state.controller.address,
    state.cc.address,
  ]);
  state.dist = await Factories.YieldDistributorV1.connectAndDeploy(deployer, 'yieldDist', [
    state.controller.address,
    state.cc.address,
  ]);

  state.premToken = await Factories.MockERC20.connectAndDeploy(deployer, 'premToken', ['Premium', 'Prem', 18]);

  const joinExtension = await Factories.JoinablePoolExtension.connectAndDeploy(deployer, 'joinableExt', [
    state.controller.address,
    1e10,
    state.cc.address,
  ]);
  const extension = await Factories.ImperpetualPoolExtension.connectAndDeploy(deployer, 'ext', [
    state.controller.address,
    1e10,
    state.cc.address,
  ]);
  const insurerV1ref = await Factories.ImperpetualPoolV1.connectAndDeploy(deployer, 'insurer', [
    extension.address,
    joinExtension.address,
  ]);
  const insuredV1ref = await Factories.InsuredPoolV1.connectAndDeploy(deployer, 'insured', [
    state.controller.address,
    state.cc.address,
  ]);

  await state.controller.setAnyRoleMode(true);
  await state.controller.setAddress(AccessFlags.PROXY_FACTORY, state.proxyCatalog.address);
  await state.controller.setAddress(AccessFlags.APPROVAL_CATALOG, state.approvalCatalog.address);
  await state.controller.setAddress(AccessFlags.PRICE_ROUTER, state.oracle.address);
  await state.proxyCatalog.setAccess([formatBytes32String('INSURED_POOL')], [MAX_UINT]);
  await state.proxyCatalog.addAuthenticImplementation(insurerV1ref.address, insurerImplName, state.cc.address);
  await state.proxyCatalog.addAuthenticImplementation(insuredV1ref.address, insuredImplName, state.cc.address);
  await state.proxyCatalog.setDefaultImplementation(insurerV1ref.address);
  await state.proxyCatalog.setDefaultImplementation(insuredV1ref.address);

  const cid = formatBytes32String('policy1');
  await Events.ApplicationSubmitted.waitOne(
    state.approvalCatalog.connect(deployer).submitApplication(cid, state.cc.address),
    (ev) => {
      state.insured = Factories.InsuredPoolV1.attach(ev.insured);
    }
  );

  const policy: IApprovalCatalog.ApprovedPolicyStruct = {
    insured: state.insured.address,
    requestCid: cid,
    approvalCid: cid,
    applied: false,
    policyName: 'policy 1',
    policySymbol: 'PL1',
    riskLevel: 1,
    basePremiumRate: 1,
    premiumToken: state.premToken.address,
    minPrepayValue: 1,
    rollingAdvanceWindow: 1,
    expiresAt: 2 ** 31,
  };
  await state.controller.grantAnyRoles(deployer.address, AccessFlags.UNDERWRITER_POLICY);
  await state.approvalCatalog.connect(deployer).approveApplication(policy);

  state.insurer = insurerV1ref;

  await state.controller.grantAnyRoles(deployer.address, AccessFlags.PRICE_ROUTER_ADMIN);
  await state.oracle.setStaticPrices([state.premToken.address], [WAD]);
  await state.premToken.mint(state.insured.address, WAD);

  await state.controller.revokeAllRoles(deployer.address);
  return state;
}

export async function setInsurer(state: State, deployer: SignerWithAddress, governor: string): Promise<void> {
  const params: WeightedPoolParamsStruct = {
    maxAdvanceUnits: 100_000_000,
    minAdvanceUnits: 1_000,
    riskWeightTarget: 10_00,
    minInsuredSharePct: 1_00,
    maxInsuredSharePct: 15_00,
    minUnitsPerRound: 10,
    maxUnitsPerRound: 20,
    overUnitsPerRound: 30,
    coveragePrepayPct: 100_00,
    maxUserDrawdownPct: 0,
    unitsPerAutoPull: 0,
  };

  await Events.ProxyCreated.waitOne(
    state.proxyCatalog
      .connect(deployer)
      .createProxy(
        deployer.address,
        insurerImplName,
        state.cc.address,
        state.insurer.interface.encodeFunctionData('initializeWeighted', [governor, 'Test', 'TST', params])
      ),
    (ev) => {
      state.insurer = Factories.ImperpetualPoolV1.attach(ev.proxy); // eslint-disable-line no-param-reassign
    }
  );
}
