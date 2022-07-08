import * as types from '../types';

import { addNamedDeployable, NamedDeployable, wrap, mock } from './factory-wrapper';

export const Factories = {
  PriceOracle: wrap(types.PriceOracle__factory),
  JoinablePoolExtension: wrap(types.JoinablePoolExtension__factory),
  PerpetualPoolExtension: wrap(types.PerpetualPoolExtension__factory),
  ImperpetualPoolExtension: wrap(types.ImperpetualPoolExtension__factory),

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
};

Object.entries(Factories).forEach(([name, factory]) => addNamedDeployable(factory, name));

export const factoryByName = (s: string): NamedDeployable => Factories[s] as NamedDeployable;
