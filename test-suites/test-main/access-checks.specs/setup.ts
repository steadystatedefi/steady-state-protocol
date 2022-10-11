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
  MockMinter,
  MockStrategy,
  OracleRouterV1,
  PremiumFundV1,
  ProxyCatalog,
  ReinvestorV1,
} from '../../../types';
import { CollateralFundV1Interface } from '../../../types/contracts/funds/CollateralFundV1';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';
import { ImperpetualPoolV1Interface } from '../../../types/contracts/insurer/ImperpetualPoolV1';

const insurerImplName = formatBytes32String('IMPERPETUAL_INDEX_POOL');
const insuredImplName = formatBytes32String('INSURED_POOL');
const fundImplName = formatBytes32String('FUND');

export type State = {
  controller: AccessController;
  proxyCatalog: ProxyCatalog;
  approvalCatalog: ApprovalCatalog;
  cc: CollateralCurrency;
  fund: CollateralFundV1;
  oracle: OracleRouterV1;
  premiumFund: PremiumFundV1;
  reinvestor: ReinvestorV1;
  strat: MockStrategy;

  insured: InsuredPoolV1;
  insurer: ImperpetualPoolV1;
  premToken: MockERC20;

  fundFuses: BigNumberish;
  insurerInterface: ImperpetualPoolV1Interface;
  fundInterface: CollateralFundV1Interface;
};

export async function makeMockMinter(state: State, deployer: SignerWithAddress): Promise<MockMinter> {
  const minterId = formatBytes32String('Minter');
  const minterImpl = await Factories.MockMinter.deploy(state.cc.address);
  await state.proxyCatalog.addAuthenticImplementation(minterImpl.address, minterId, state.cc.address);
  await state.proxyCatalog.setDefaultImplementation(minterImpl.address);

  let minter!: MockMinter;
  await Events.ProxyCreated.waitOne(
    state.proxyCatalog.createProxy(deployer.address, minterId, state.cc.address, []),
    (ev) => {
      minter = Factories.MockMinter.attach(ev.proxy);
    }
  );

  return minter;
}

async function populateProxyCatalog(state: State, deployer: SignerWithAddress) {
  const fundRef = await Factories.CollateralFundV1.connectAndDeploy(deployer, 'fund', [
    state.controller.address,
    state.cc.address,
    state.fundFuses,
  ]);
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

  await state.proxyCatalog.addAuthenticImplementation(fundRef.address, fundImplName, state.cc.address);
  await state.proxyCatalog.setAccess([insuredImplName], [MAX_UINT]);
  await state.proxyCatalog.addAuthenticImplementation(insurerV1ref.address, insurerImplName, state.cc.address);
  await state.proxyCatalog.addAuthenticImplementation(insuredV1ref.address, insuredImplName, state.cc.address);
  await state.proxyCatalog.setDefaultImplementation(insurerV1ref.address);
  await state.proxyCatalog.setDefaultImplementation(insuredV1ref.address);
  await state.proxyCatalog.setDefaultImplementation(fundRef.address);

  state.insurerInterface = insurerV1ref.interface; // eslint-disable-line no-param-reassign
  state.fundInterface = fundRef.interface; // eslint-disable-line no-param-reassign
}

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
  state.cc = await Factories.CollateralCurrencyV1.connectAndDeploy(deployer, 'cc', [state.controller.address]);
  state.oracle = await Factories.OracleRouterV1.connectAndDeploy(deployer, 'oracle', [
    state.controller.address,
    state.cc.address,
  ]);
  state.premiumFund = await Factories.PremiumFundV1.connectAndDeploy(deployer, 'premiumFund', [
    state.controller.address,
    state.cc.address,
  ]);
  state.reinvestor = await Factories.ReinvestorV1.connectAndDeploy(deployer, 'reinvestor', [
    state.controller.address,
    state.cc.address,
  ]);
  state.strat = await Factories.MockStrategy.connectAndDeploy(deployer, 'strategy1', []);
  state.premToken = await Factories.MockERC20.connectAndDeploy(deployer, 'premToken', ['Premium', 'Prem', 18]);

  await populateProxyCatalog(state, deployer);
  await state.controller.setAnyRoleMode(true);
  await state.controller.setAddress(AccessFlags.PROXY_FACTORY, state.proxyCatalog.address);
  await state.controller.setAddress(AccessFlags.APPROVAL_CATALOG, state.approvalCatalog.address);
  await state.controller.setAddress(AccessFlags.PRICE_ROUTER, state.oracle.address);

  await Events.ProxyCreated.waitOne(
    state.proxyCatalog
      .connect(deployer)
      .createProxy(
        deployer.address,
        fundImplName,
        state.cc.address,
        state.fundInterface.encodeFunctionData('initializeCollateralFund')
      ),
    (ev) => {
      state.fund = Factories.CollateralFundV1.attach(ev.proxy);
    }
  );

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
    riskLevel: 0,
    basePremiumRate: 1,
    premiumToken: state.premToken.address,
    minPrepayValue: 1,
    rollingAdvanceWindow: 1,
    expiresAt: 2 ** 31,
  };
  await state.controller.grantAnyRoles(deployer.address, AccessFlags.UNDERWRITER_POLICY);
  await state.approvalCatalog.connect(deployer).approveApplication(policy);

  await state.controller.grantAnyRoles(
    deployer.address,
    AccessFlags.PRICE_ROUTER_ADMIN | AccessFlags.PRICE_ROUTER_ADMIN
  );
  await state.oracle.setStaticPrices([state.premToken.address], [WAD]);
  await state.oracle.configureSourceGroup(state.fund.address, state.fundFuses);
  await state.premToken.mint(state.insured.address, WAD);
  await state.cc.setBorrowManager(state.reinvestor.address);
  await state.controller.revokeAllRoles(deployer.address);

  await state.premToken.mint(deployer.address, WAD.mul(2));
  await state.premToken.approve(state.fund.address, MAX_UINT);
  return state;
}

export async function setInsurer(state: State, deployer: SignerWithAddress, governor: string): Promise<void> {
  const params: WeightedPoolParamsStruct = {
    maxAdvanceUnits: 100_000_000,
    minAdvanceUnits: 1_000,
    riskWeightTarget: 1_00,
    minInsuredSharePct: 1_00,
    maxInsuredSharePct: 100_00,
    minUnitsPerRound: 10,
    maxUnitsPerRound: 20,
    overUnitsPerRound: 30,
    coverageForepayPct: 100_00,
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
        state.insurerInterface.encodeFunctionData('initializeWeighted', [governor, 'Test', 'TST', params])
      ),
    (ev) => {
      state.insurer = Factories.ImperpetualPoolV1.attach(ev.proxy); // eslint-disable-line no-param-reassign
    }
  );

  await state.controller.grantAnyRoles(deployer.address, AccessFlags.INSURER_ADMIN);
  await state.cc.registerInsurer(state.insurer.address);
  await state.controller.revokeAllRoles(deployer.address);
}
