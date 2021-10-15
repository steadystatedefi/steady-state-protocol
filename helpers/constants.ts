import BigNumber from 'bignumber.js';

export const DAY = 60 * 60 * 24;
export const WEEK = 7 * DAY;

export const WAD_NUM = Math.pow(10, 18);
export const WAD = WAD_NUM.toString();
export const HALF_WAD = new BigNumber(WAD).multipliedBy(0.5).toString();
export const RAY = new BigNumber(10).exponentiatedBy(27).toFixed();
export const HALF_RAY = new BigNumber(RAY).multipliedBy(0.5).toFixed();
export const WAD_RAY_RATIO_NUM = Math.pow(10, 9);
export const WAD_RAY_RATIO = WAD_RAY_RATIO_NUM.toString();
export const oneWad = new BigNumber(Math.pow(10, 18));
export const oneEther = new BigNumber(Math.pow(10, 18));
export const oneRay = new BigNumber(Math.pow(10, 27));
export const RAY_100 = oneRay.multipliedBy(100).toFixed();
export const RAY_10000 = oneRay.multipliedBy(10000).toFixed();
export const MAX_UINT_AMOUNT = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
export const ONE_ADDRESS = '0x0000000000000000000000000000000000000001';
export const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const USD_ADDRESS = '0x10F7Fc1F91Ba351f9C629c5947AD69bD03C05b96';
export const MOCK_USD_PRICE_IN_WEI = '5848466240000000';