import * as types from '../types';

import { addNamedDeployable, NamedDeployable, wrap, mock } from './factory-wrapper';

export const Factories = {
  JoinablePoolExtension: wrap(types.JoinablePoolExtension__factory),
  PerpetualPoolExtension: wrap(types.PerpetualPoolExtension__factory),
  ImperpetualPoolExtension: wrap(types.ImperpetualPoolExtension__factory),
  AccessController: wrap(types.AccessController__factory),
  ProxyCatalog: wrap(types.ProxyCatalog__factory),
  TransparentProxy: wrap(types.TransparentProxy__factory),
  ApprovalCatalogV1: wrap(types.ApprovalCatalogV1__factory),
  InsuredPoolV1: wrap(types.InsuredPoolV1__factory),
  CollateralCurrency: wrap(types.CollateralCurrency__factory),
  OracleRouterV1: wrap(types.OracleRouterV1__factory),
  CollateralFundV1: wrap(types.CollateralFundV1__factory),
  PremiumFundV1: wrap(types.PremiumFundV1__factory),
  YieldDistributorV1: wrap(types.YieldDistributorV1__factory),
  ImperpetualPoolV1: wrap(types.ImperpetualPoolV1__factory),

  MockCollateralCurrency: wrap(types.MockCollateralCurrency__factory),
  MockWeightedRounds: mock(types.MockWeightedRounds__factory),
  MockCollateralCurrencyStub: mock(types.MockCollateralCurrencyStub__factory),
  MockPerpetualPool: mock(types.MockPerpetualPool__factory),
  MockImperpetualPool: mock(types.MockImperpetualPool__factory),
  MockInsuredPool: mock(types.MockInsuredPool__factory),
  MockBalancerLib2: mock(types.MockBalancerLib2__factory),
  MockPremiumFund: mock(types.MockPremiumFund__factory),
  MockPremiumActuary: mock(types.MockPremiumActuary__factory),
  MockPremiumSource: mock(types.MockPremiumSource__factory),
  MockERC20: mock(types.MockERC20__factory),
  MockCollateralFund: mock(types.MockCollateralFund__factory),
  MockLibs: mock(types.MockLibs__factory),
  MockCaller: mock(types.MockCaller__factory),
  MockVersionedInitializable1: mock(types.MockVersionedInitializable1__factory),
  MockVersionedInitializable2: mock(types.MockVersionedInitializable2__factory),
  MockChainlinkV3: mock(types.MockChainlinkV3__factory),
  MockUniswapV2: mock(types.MockUniswapV2__factory),
  MockYieldDistributor: mock(types.MockYieldDistributor__factory),
  MockInsurerForYield: mock(types.MockInsurerForYield__factory),
  MockInsuredPoolV2: mock(types.MockInsuredPoolV2__factory),
};

Object.entries(Factories).forEach(([name, factory]) => addNamedDeployable(factory, name));

export const factoryByName = (s: string): NamedDeployable => Factories[s] as NamedDeployable;
