import { MAX_UINT } from '../constants';
import { IConfiguration } from '../types';

export enum EAccessRoles {
  EMERGENCY_ADMIN = 2 ** 0,
  TREASURY_ADMIN = 2 ** 1,
  COLLATERAL_FUND_ADMIN = 2 ** 2,
  INSURER_ADMIN = 2 ** 3,
  INSURER_OPS = 2 ** 4,
  PREMIUM_FUND_ADMIN = 2 ** 5,
  SWEEP_ADMIN = 2 ** 6,
  ORACLE_ADMIN = 2 ** 7,
  UNDERWRITER_POLICY = 2 ** 8,
  UNDERWRITER_CLAIM = 2 ** 9,
}

const ROLES = MAX_UINT.mask(16);
const SINGLETS = MAX_UINT.mask(64).xor(ROLES);
const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES);

export const FullConfig: IConfiguration = {
  Owner: {},
  DepositTokens: {},
  AccessController: {
    ROLES,
    SINGLETS,
    PROTECTED_SINGLETS,
  },
};
