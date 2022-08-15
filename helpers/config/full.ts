import { ENetwork } from '../config-networks';
import { IConfiguration, INetworkConfiguration } from '../config-types';
import { WAD } from '../constants';

type FullTokens = 'USDC' | 'USD';

const configMain: INetworkConfiguration<FullTokens> = {
  Assets: {
    USDC: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
  },
  Commons: {
    unitSize: WAD,
  },
  CollateralCurrency: {
    name: 'USD-equivalent collateral',
    symbol: '$CC',
    quoteToken: 'USD',
  },
  CollateralFund: {
    fuseMask: 1,
  },
  Dependencies: {},
  PriceFeeds: {
    USDC: {
      decimals: 18,
      value: WAD,
    },
  },
  IndexPools: [
    {
      poolType: 'IMPERPETUAL_INDEX_POOL',
      initializer: 'initializeWeighted',
      initParams: [
        'Index Pool Token',
        '$PT',
        {
          maxAdvanceUnits: 10000,
          minAdvanceUnits: 1000,
          riskWeightTarget: 1000, // 10%
          minInsuredSharePct: 100, // 1%
          maxInsuredSharePct: 4000, // 40%
          minUnitsPerRound: 20,
          maxUnitsPerRound: 20,
          overUnitsPerRound: 30,
          coveragePrepayPct: 9000, // 90%
          maxUserDrawdownPct: 1000, // 10%
          unitsPerAutoPull: 0,
        },
      ],
    },
  ],
};

export const FullConfig: IConfiguration<ENetwork> = {
  main: configMain,
  hardhat: configMain,
};
