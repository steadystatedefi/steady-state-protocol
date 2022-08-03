import { BigNumber } from 'ethers';

import { MAX_UINT } from './constants';

export const ROLES = MAX_UINT.mask(16);
export const SINGLETS = MAX_UINT.mask(64).xor(ROLES);
export const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES);

export const EMERGENCY_ADMIN = BigNumber.from(1).shl(0);
export const TREASURY_ADMIN = BigNumber.from(1).shl(1);
export const COLLATERAL_FUND_ADMIN = BigNumber.from(1).shl(2);
export const INSURER_ADMIN = BigNumber.from(1).shl(3);
export const INSURER_OPS = BigNumber.from(1).shl(4);

export const PREMIUM_FUND_ADMIN = BigNumber.from(1).shl(5);

export const SWEEP_ADMIN = BigNumber.from(1).shl(6);
export const PRICE_ROUTER_ADMIN = BigNumber.from(1).shl(7);

export const UNDERWRITER_POLICY = BigNumber.from(1).shl(8);
export const UNDERWRITER_CLAIM = BigNumber.from(1).shl(9);

export const LP_DEPLOY = BigNumber.from(1).shl(10);
export const LP_ADMIN = BigNumber.from(1).shl(11);

export const INSURED_ADMIN = BigNumber.from(1).shl(12);
export const INSURED_OPS = BigNumber.from(1).shl(13);
export const BORROWER_ADMIN = BigNumber.from(1).shl(14);
export const LIQUIDITY_BORROWER = BigNumber.from(1).shl(15);

// protected singletons - use for proxies
export const APPROVAL_CATALOG = BigNumber.from(1).shl(16);
export const TREASURY = BigNumber.from(1).shl(17);
// export const COLLATERAL_CURRENCY = BigNumber.from(1).shl(18);

// non-proxied singletons, numbered down from 31 (as JS has problems with bitmasks over 31 bits)
export const PROXY_FACTORY = BigNumber.from(1).shl(26);

export const DATA_HELPER = BigNumber.from(1).shl(28);
export const PRICE_ROUTER = BigNumber.from(1).shl(29);

// any other roles - use range [64..]
// these roles can be assigned to multiple addresses
export const COLLATERAL_FUND_LISTING = BigNumber.from(1).shl(64); // an ephemeral role - just to keep a list of collateral funds
export const INSURER_POOL_LISTING = BigNumber.from(1).shl(65); // an ephemeral role - just to keep a list of insurer funds
