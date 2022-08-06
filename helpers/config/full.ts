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

export const FullConfig: IConfiguration = {
  Owner: {},
  DepositTokens: {},
};
