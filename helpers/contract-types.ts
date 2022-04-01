import { addNamedDeployable, NamedDeployable, wrap, mock } from "./factory-wrapper";
import * as types from "../types";

export const Factories = {
  PriceOracle: wrap(types.PriceOracleFactory),
  WeightedPoolExtension: wrap(types.WeightedPoolExtensionFactory),
  PremiumCollector: wrap(types.PremiumCollectorFactory),
  CollateralCurrency: wrap(types.CollateralCurrencyFactory),

  MockWeightedRounds: mock(types.MockWeightedRoundsFactory),
  MockCollateralCurrency: mock(types.MockCollateralCurrencyFactory),
  MockWeightedPool: mock(types.MockWeightedPoolFactory),
  MockInsuredPool: mock(types.MockInsuredPoolFactory),  
}

Object.entries(Factories).forEach(([name, factory]) => addNamedDeployable(factory, name));

export const factoryByName = (s: string): NamedDeployable => {
  return Factories[s];
};
