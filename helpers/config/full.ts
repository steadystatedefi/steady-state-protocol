import { ENetwork } from '../config-networks';
import { IConfiguration, INetworkConfiguration } from '../config-types';
import { WAD } from '../constants';
import { BalancerAssetMode } from '../types-balancer';

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
          riskWeightTarget: 10_00, // 10%
          minInsuredSharePct: 1_00, // 1%
          maxInsuredSharePct: 40_00, // 40%
          minUnitsPerRound: 20,
          maxUnitsPerRound: 20,
          overUnitsPerRound: 30,
          coverageForepayPct: 90_00, // 90%
          maxUserDrawdownPct: 10_00, // 10%
          unitsPerAutoPull: 0,
        },
      ],
    },
  ],
  PremiumFund: {
    drawdownTokenConfig: {
      mode: BalancerAssetMode.AssetRateMultiplier,
      w: 0,
      n: 60, // 1 minute
    },
    premiumTokenConfig: {
      mode: BalancerAssetMode.AssetRateMultiplier,
      w: 0,
      n: 20_00, // 20% - premium token is not rate-balanced, but share-based
    },
  },
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
