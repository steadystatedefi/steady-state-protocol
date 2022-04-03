import { addNamedDeployable, NamedDeployable, wrap, mock } from "./factory-wrapper";
import * as types from "../types";

export const Factories = {
  PriceOracle: wrap(types.PriceOracleFactory),
  WeightedPoolExtension: wrap(types.WeightedPoolExtensionFactory),
  PremiumCollector: wrap(types.PremiumCollectorFactory),
  TradeableToken: wrap(types.TradeableTokenFactory),
  GenericStakingPool: wrap(types.GenericStakingFactory),

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
