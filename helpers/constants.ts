import { BigNumber } from 'ethers';

export const DAY = 60 * 60 * 24;
export const WEEK = 7 * DAY;
export const YEAR = 365 * DAY;

export const WAD_NUM = 10 ** 18;
export const WAD = BigNumber.from(10).pow(18);
export const HALF_WAD = WAD.div(2);
export const RAY = BigNumber.from(10).pow(27);
export const HALF_RAY = RAY.div(2);
export const WAD_RAY_RATIO_NUM = 10 ** 9;
export const WAD_RAY_RATIO = BigNumber.from(WAD_RAY_RATIO_NUM);
export const MAX_UINT128 = BigNumber.from(2).pow(128).sub(1);
export const MAX_UINT_STR = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
export const MAX_UINT = BigNumber.from(MAX_UINT_STR);
export const ZERO = BigNumber.from(0);
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
export const ONE_ADDRESS = '0x0000000000000000000000000000000000000001';
export const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const USD_ADDRESS = '0x10F7Fc1F91Ba351f9C629c5947AD69bD03C05b96';

export const MAX_UINT144 = BigNumber.from(1).shl(144).sub(1);
export const MAX_UINT64 = BigNumber.from(1).shl(64).sub(1);
export const MAX_UINT32 = BigNumber.from(1).shl(32).sub(1);
