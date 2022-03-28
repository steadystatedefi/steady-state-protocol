import { addNamedDeployable, NamedDeployable, wrap, mock } from "./factory-wrapper";
import * as types from "../types";
//import { MockStable } from "../types/MockStable";
//import { MockStableFactory } from "../types/MockStableFactory";

export const Factories = {
  PriceOracle: wrap(types.PriceOracleFactory),
  WeightedPoolExtension: wrap(types.WeightedPoolExtensionFactory),
  PremiumCollector: wrap(types.PremiumCollectorFactory),
  NoYieldToken: wrap(types.NoYieldTokenFactory),

  MockWeightedRounds: mock(types.MockWeightedRoundsFactory),
  MockCollateralFund: mock(types.MockCollateralFundFactory),
  MockWeightedPool: mock(types.MockWeightedPoolFactory),
  MockInsuredPool: mock(types.MockInsuredPoolFactory),
  MockPremiumEarningPool: mock(types.MockPremiumEarningPoolFactory),
  MockStable: mock(types.MockStableFactory),
}

Object.entries(Factories).forEach(([name, factory]) => addNamedDeployable(factory, name));

export const factoryByName = (s: string): NamedDeployable => {
  return Factories[s];
};
