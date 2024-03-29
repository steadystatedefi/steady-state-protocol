export const ProxyTypes = {
  APPROVAL_CATALOG: 'APPROVAL_CATALOG',
  ORACLE_ROUTER: 'ORACLE_ROUTER',
  COLLATERAL_CCY: 'COLLATERAL_CCY',
  COLLATERAL_FUND: 'COLLATERAL_FUND',
  REINVESTOR: 'REINVESTOR',
  PREMIUM_FUND: 'PREMIUM_FUND',
  IMPERPETUAL_INDEX_POOL: 'IMPERPETUAL_INDEX_POOL',
  INSURED_POOL: 'INSURED_POOL',
} as const;

export enum PriceFeedType {
  StaticValue,
  ChainLinkV3,
  UniSwapV2Pair,
}
