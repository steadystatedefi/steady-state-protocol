import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';

import { ROLES, SINGLETS, PROTECTED_SINGLETS } from '../../../helpers/access-control-constants';
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

export type State = {
  controller: AccessController;
  proxyCatalog: ProxyCatalog;
  approvalCatalog: ApprovalCatalog;
  cc: CollateralCurrency;
  fund: CollateralFundV1;
  oracle: OracleRouterV1;
  premiumFund: PremiumFundV1;
  dist: YieldDistributorV1;

  insuredV1: InsuredPoolV1;
  insurerV1: ImperpetualPoolV1;

  fundFuses: BigNumberish;
};

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
  state.insurerV1 = await Factories.ImperpetualPoolV1.connectAndDeploy(deployer, 'insurer', [
    extension.address,
    joinExtension.address,
  ]);
  state.insuredV1 = await Factories.InsuredPoolV1.connectAndDeploy(deployer, 'insured', [
    state.controller.address,
    state.cc.address,
  ]);

  return state;
}
