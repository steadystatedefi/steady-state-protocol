import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { ROLES, SINGLETS, PROTECTED_SINGLETS } from '../../../helpers/access-control-constants';
import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import {
  AccessController,
  ApprovalCatalog,
  CollateralCurrency,
  CollateralFundV1,
  ImperpetualPoolV1,
  InsuredPoolV1,
  OracleRouterV1,
  PremiumFundV1,
  ProxyCatalog,
  YieldDistributorV1,
} from '../../../types';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';

const insurerImplName = formatBytes32String('insurer');
const insuredImplName = formatBytes32String('insured');

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

  fundFuses: BigNumberish;
};

// The returned state's insurerv1 is *not* initialized and must be
export async function deployAccessControlState(deployer: SignerWithAddress): Promise<State> {
  const state: State = {} as State;
  state.fundFuses = 2;
  state.controller = await Factories.AccessController.connectAndDeploy(deployer, 'controller', [
    SINGLETS,
    ROLES,
    PROTECTED_SINGLETS,
  ]);
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

  await state.proxyCatalog.addAuthenticImplementation(insurerV1ref.address, insurerImplName);
  await state.proxyCatalog.addAuthenticImplementation(insuredV1ref.address, insuredImplName);
  await state.proxyCatalog.setDefaultImplementation(insurerV1ref.address);
  await state.proxyCatalog.setDefaultImplementation(insuredV1ref.address);

  await Events.ProxyCreated.waitOne(
    state.proxyCatalog.createProxy(
      deployer.address,
      insuredImplName,
      insuredV1ref.interface.encodeFunctionData('initializeInsured', [deployer.address])
    ),
    (ev) => {
      state.insured = Factories.InsuredPoolV1.attach(ev.proxy);
    }
  );

  state.insurer = insurerV1ref;

  return state;
}

export async function setInsurer(state: State, deployer: SignerWithAddress, governor: string): Promise<void> {
  const params: WeightedPoolParamsStruct = {
    maxAdvanceUnits: 10000,
    minAdvanceUnits: 1000,
    riskWeightTarget: 1000, // 10%
    minInsuredShare: 100, // 1%
    maxInsuredShare: 4000, // 25%
    minUnitsPerRound: 20,
    maxUnitsPerRound: 20,
    overUnitsPerRound: 30,
    coveragePrepayPct: 9000, // 90%
    maxUserDrawdownPct: 1000,
  };

  await Events.ProxyCreated.waitOne(
    state.proxyCatalog
      .connect(deployer)
      .createProxy(
        deployer.address,
        insurerImplName,
        state.insurer.interface.encodeFunctionData('initializeWeighted', [governor, 'Test', 'TST', params])
      ),
    (ev) => {
      state.insurer = Factories.ImperpetualPoolV1.attach(ev.proxy); // eslint-disable-line no-param-reassign
    }
  );
}
