import { ENetwork } from '../config-networks';
import { IConfiguration, INetworkConfiguration } from '../config-types';
import { WAD } from '../constants';

type FullTokens = 'USDC' | 'USD';

const configTemplate: Omit<INetworkConfiguration<FullTokens>, 'Assets' | 'PriceFeeds'> = {
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
    assets: {
      USDC: {},
    },
  },
  Dependencies: {},
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
  goerli: {
    ...configTemplate,
    Assets: {
      USDC: '0x07865c6E87B9F70255377e024ace6630C1Eaa37F',
    },
    PriceFeeds: {
      USDC: {
        decimals: 6,
        value: WAD,
      },
    },
  },
  hardhat: {
    ...configTemplate,
    Assets: {
      USDC: '0x07865c6E87B9F70255377e024ace6630C1Eaa37F',
    },
    PriceFeeds: {
      USDC: {
        decimals: 6,
        value: WAD,
      },
    },
  },
};
