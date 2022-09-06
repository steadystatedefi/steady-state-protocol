import { BigNumber } from 'ethers';

export type AccessFlag = number | BigNumber;

export const AccessFlags = {
  // roles that can be assigned to multiple addresses - use range [0..15]
  EMERGENCY_ADMIN: 1 << 0,
  TREASURY_ADMIN: 1 << 1,
  COLLATERAL_FUND_ADMIN: 1 << 2,
  INSURER_ADMIN: 1 << 3,
  INSURER_OPS: 1 << 4,

  PREMIUM_FUND_ADMIN: 1 << 5,

  SWEEP_ADMIN: 1 << 6,
  PRICE_ROUTER_ADMIN: 1 << 7,

  UNDERWRITER_POLICY: 1 << 8,
  UNDERWRITER_CLAIM: 1 << 9,

  LP_DEPLOY: 1 << 10,
  LP_ADMIN: 1 << 11,

  INSURED_ADMIN: 1 << 12,
  INSURED_OPS: 1 << 13,
  BORROWER_ADMIN: 1 << 14,
  LIQUIDITY_BORROWER: 1 << 15,

  // protected singletons - use for proxies
  APPROVAL_CATALOG: 1 << 16,
  TREASURY: 1 << 17,
  // COLLATERAL_CURRENCY: 1 << 18;
  PRICE_ROUTER: 1 << 19,

  // non-proxied singletons, numbered down from 31 (as JS has problems with bitmasks over 31 bits)
  PROXY_FACTORY: 1 << 26,

  DATA_HELPER: 1 << 28,

  // any other roles - use range [64..]
  // these roles can be assigned to multiple addresses
  COLLATERAL_FUND_LISTING: BigNumber.from(1).shl(64), // an ephemeral role - just to keep a list of collateral funds
  INSURER_POOL_LISTING: BigNumber.from(1).shl(65), // an ephemeral role - just to keep a list of insurer funds
} as const;
