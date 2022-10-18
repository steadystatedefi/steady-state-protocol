import * as types from '../types';

import { wrap, mock, iface, loadFactories, NamedAttachable } from './factory-wrapper';

export const Factories = {
  IERC20: iface(types.IERC20Detailed__factory),
  IInsurerPool: iface(types.IInsurerPool__factory),
  ICancellableCoverage: iface(types.ICancellableCoverage__factory),
  ICoverageDistributor: iface(types.ICoverageDistributor__factory),
  WeightedPoolExtension: iface(types.WeightedPoolExtension__factory),

  JoinablePoolExtension: wrap(types.JoinablePoolExtension__factory),
  PerpetualPoolExtension: wrap(types.PerpetualPoolExtension__factory),
  ImperpetualPoolExtension: wrap(types.ImperpetualPoolExtension__factory),
  ImperpetualPoolV1: wrap(types.ImperpetualPoolV1__factory),
  AccessController: wrap(types.AccessController__factory),
  ProxyCatalog: wrap(types.ProxyCatalog__factory),
  TransparentProxy: wrap(types.TransparentProxy__factory),
  ApprovalCatalogV1: wrap(types.ApprovalCatalogV1__factory),
  InsuredPoolV1: wrap(types.InsuredPoolV1__factory),
  CollateralCurrencyV1: wrap(types.CollateralCurrencyV1__factory),
  FrontHelper: wrap(types.FrontHelper__factory),
  OracleRouterV1: wrap(types.OracleRouterV1__factory),
  CollateralFundV1: wrap(types.CollateralFundV1__factory),
  PremiumFundV1: wrap(types.PremiumFundV1__factory),

  ReinvestorV1: wrap(types.ReinvestorV1__factory),
  AaveStrategy: wrap(types.AaveStrategy__factory),

  MockAccessController: wrap(types.MockAccessController__factory),
  MockCollateralCurrency: mock(types.MockCollateralCurrency__factory),
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
  MockInsuredPoolV2: mock(types.MockInsuredPoolV2__factory),
  MockCancellableImperpetualPool: mock(types.MockCancellableImperpetualPool__factory),
  MockReinvestManager: mock(types.MockReinvestManager__factory),
  MockStrategy: mock(types.MockStrategy__factory),
  MockAavePoolV3: mock(types.MockAavePoolV3__factory),
  MockMinter: mock(types.MockMinter__factory),
};

loadFactories(Factories);

export function findFactory(name: string): NamedAttachable {
  return Factories[name] as NamedAttachable;
}

export function getFactory(name: string): NamedAttachable {
  const factory = Factories[name] as NamedAttachable;
  if (!factory) {
    throw new Error(`Unknown type factory name: ${name}`);
  }
  return factory;
}
