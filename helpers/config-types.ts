import { BigNumber, BigNumberish } from 'ethers';

import { WeightedPoolParamsStruct } from '../types/contracts/insurer/WeightedPoolBase';

import { ETH_ADDRESS, USD_ADDRESS } from './constants';
import { ProxyTypes } from './proxy-types';
import { falsyOrZeroAddress } from './runtime-utils';
import { EthereumAddress } from './types';

export type IAssets<T> = Record<string, T>;

export type ParamPer<K extends string, T> = Record<K, T>;
export type ParamPerOpt<K extends string, T> = Partial<Record<K, T>>;

export interface ITokenDetails {
  name: string;
  symbol: string;
}

export interface ICollateralCurrency<K extends string> extends ITokenDetails {
  quoteToken: K;
}

export interface ICollateralFundAsset {
  trustee?: EthereumAddress;
}

export interface ICollateralFund<K extends string> {
  fuseMask: BigNumberish;
  assets?: ParamPerOpt<K, ICollateralFundAsset>;
}

export interface IPriceBase<K extends string> {
  decimals: number;
  xPrice?: K | true;
  priceRange?: {
    target: BigNumber;
    tolerance: number;
  };
}

export interface IPriceStatic<K extends string = string> extends IPriceBase<K> {
  value: BigNumber;
}

export interface IPriceFeed<K extends string = string> extends IPriceBase<K> {
  source?: EthereumAddress;
  sourceType: 'uniswap2' | 'chainlink' | number;
}

export interface IDependencies {
  UniswapV2Router?: EthereumAddress;
}

export interface IBaseIndexPoolInit {
  poolType: string;
  initializer: string;
  governor?: EthereumAddress;
  initParams: unknown[];
}

export interface IWeightedIndexPoolInit extends IBaseIndexPoolInit {
  poolType: typeof ProxyTypes.IMPERPETUAL_INDEX_POOL; // | 'PERPETUAL_INDEX_POOL';
  initializer: 'initializeWeighted';
  governor?: EthereumAddress;
  initParams: [tokenName: string, tokenSymbol: string, params: WeightedPoolParamsStruct];
}

export type IIndexPoolConfig = IWeightedIndexPoolInit; // | IDirectInsurerPool

const simulatedAssets = {
  USD: USD_ADDRESS,
  ETH: ETH_ADDRESS,
};

type RealAssets<Tokens extends string> = Exclude<Tokens, keyof typeof simulatedAssets>;

export interface INetworkConfiguration<Tokens extends string = string> {
  Owner?: EthereumAddress;
  EmergencyAdmins?: EthereumAddress[];
  Assets: ParamPer<RealAssets<Tokens>, EthereumAddress>;
  CollateralCurrency: ICollateralCurrency<Tokens>;
  CollateralFund: ICollateralFund<RealAssets<Tokens>>;
  Dependencies: IDependencies;
  // price oracle quote
  PriceFeeds: ParamPerOpt<Tokens, IPriceStatic<Tokens> | IPriceFeed<Tokens>>;
  IndexPools: IIndexPoolConfig[];
}

export type IConfiguration<Networks extends string = string> = ParamPerOpt<Networks, INetworkConfiguration<string>>;

export function findAssetAddress<Tokens extends string>(cfg: INetworkConfiguration<Tokens>, name: Tokens): string {
  return (cfg.Assets[name as RealAssets<Tokens>] ?? simulatedAssets[name as string]) as string;
}

export function getAssetAddress<Tokens extends string>(cfg: INetworkConfiguration<Tokens>, name: Tokens): string {
  const addr = findAssetAddress<Tokens>(cfg, name);
  if (falsyOrZeroAddress(addr)) {
    throw new Error(`Missing asset address: ${name}`);
  }
  return addr;
}
