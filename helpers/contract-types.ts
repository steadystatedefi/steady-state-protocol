import * as types from '../types';

import { addNamedDeployable, NamedDeployable, wrap, mock } from './factory-wrapper';

export const Factories = {
  PriceOracle: wrap(types.PriceOracle__factory),
  PerpetualPoolExtension: wrap(types.PerpetualPoolExtension__factory),
  ImperpetualPoolExtension: wrap(types.ImperpetualPoolExtension__factory),
  PremiumCollector: wrap(types.PremiumCollector__factory),
  CollateralCurrency: wrap(types.CollateralCurrency__factory),

  MockWeightedRounds: mock(types.MockWeightedRounds__factory),
  MockCollateralCurrency: mock(types.MockCollateralCurrency__factory),
  MockPerpetualPool: mock(types.MockPerpetualPool__factory),
  MockImperpetualPool: mock(types.MockImperpetualPool__factory),
  MockInsuredPool: mock(types.MockInsuredPool__factory),
};

Object.entries(Factories).forEach(([name, factory]) => addNamedDeployable(factory, name));

export const factoryByName = (s: string): NamedDeployable => Factories[s] as NamedDeployable;
