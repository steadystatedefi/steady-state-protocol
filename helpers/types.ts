import { getNetworkName } from './runtime-utils';

export interface SymbolMap<T> {
  [symbol: string]: T;
}

export type TNetwork = EEthereumNetwork | EPolygonNetwork | EOtherNetwork;

export enum EEthereumNetwork {
  kovan = 'kovan',
  ropsten = 'ropsten',
  rinkeby = 'rinkeby',
  main = 'main',
  coverage = 'coverage',
  hardhat = 'hardhat',
}

export enum EOtherNetwork {
  bsc = 'bsc',
  bsc_testnet = 'bsc_testnet',
  avalanche_testnet = 'avalanche_testnet',
  avalanche = 'avalanche',
  fantom_testnet = 'fantom_testnet',
  fantom = 'fantom',
}

export enum EPolygonNetwork {
  matic = 'matic',
  mumbai = 'mumbai',
  arbitrum_testnet = 'arbitrum_testnet',
  arbitrum = 'arbitrum',
  optimistic_testnet = 'optimistic_testnet',
  optimistic = 'optimistic',
}

export const isPolygonNetwork = (name: string): boolean => EPolygonNetwork[name] !== undefined;

export const isKnownNetworkName = (name: string): boolean =>
  isPolygonNetwork(name) || EEthereumNetwork[name] !== undefined || EOtherNetwork[name] !== undefined;

export const isAutoGasNetwork = (name: string): boolean => isPolygonNetwork(name);

export enum NetworkNames {
  kovan = 'kovan',
  ropsten = 'ropsten',
  rinkeby = 'rinkeby',
  main = 'main',
  matic = 'matic',
  mumbai = 'mumbai',
}

export type TEthereumAddress = string;

export interface IAssetCommon<T> {
  [key: string]: T;
}

export interface IAssetBase<T> {
  WETH: T;
  DAI: T;
  USDC: T;
  USDT: T;
  WBTC: T;
  USD: T;
}

const tokenSymbols: IAssetBase<string> = {
  WETH: '',
  DAI: '',
  USDC: '',
  USDT: '',
  WBTC: '',
  USD: '',
};

export type IAssetsWithoutUSD<T> = Omit<IAssetBase<T>, 'USD'>;
export type IAssetsWithoutUSDOpt<T> = OmitOpt<IAssetBase<T>, 'USD'>;

export type RecordOpt<K extends keyof unknown, T> = {
  [P in K]?: T;
};

export type PickOpt<T, K extends keyof T> = {
  [P in K]?: T[P];
};

export type AllOpt<T> = {
  [P in keyof T]?: T[P];
};

export type OmitOpt<T, K extends keyof never> = PickOpt<T, Exclude<keyof T, K>>;

export const DefaultTokenSymbols: string[] = Object.keys(tokenSymbols);

export type iParamsPerNetwork<T> = iParamsPerNetworkAll<T>;
export type iParamsPerNetworkOpt<T> = AllOpt<iParamsPerNetwork<T>>;

export interface iParamsPerNetworkAll<T>
  extends iEthereumParamsPerNetwork<T>,
    iPolygonParamsPerNetwork<T>,
    iParamsPerOtherNetwork<T> {}

export type iParamsPerNetworkGroup<T> =
  | iEthereumParamsPerNetwork<T>
  | iPolygonParamsPerNetwork<T>
  | iParamsPerOtherNetwork<T>;

export interface iEthereumParamsPerNetwork<T> {
  [EEthereumNetwork.coverage]: T;
  [EEthereumNetwork.kovan]: T;
  [EEthereumNetwork.ropsten]: T;
  [EEthereumNetwork.rinkeby]: T;
  [EEthereumNetwork.main]: T;
  [EEthereumNetwork.hardhat]: T;
}

export interface iPolygonParamsPerNetwork<T> {
  [EPolygonNetwork.matic]: T;
  [EPolygonNetwork.mumbai]: T;
  [EPolygonNetwork.arbitrum_testnet]: T;
  [EPolygonNetwork.arbitrum]: T;
  [EPolygonNetwork.optimistic_testnet]: T;
  [EPolygonNetwork.optimistic]: T;
}

export interface iParamsPerOtherNetwork<T> {
  [EOtherNetwork.bsc]: T;
  [EOtherNetwork.bsc_testnet]: T;
  [EOtherNetwork.avalanche]: T;
  [EOtherNetwork.avalanche_testnet]: T;
  [EOtherNetwork.fantom]: T;
  [EOtherNetwork.fantom_testnet]: T;
}

export interface IMocksConfig {
  UsdAddress: TEthereumAddress;
}

export interface IConfiguration {
  Owner: iParamsPerNetworkOpt<TEthereumAddress>;
  DepositTokens: iParamsPerNetworkOpt<SymbolMap<string>>;
}

export interface ITokenAddress {
  [token: string]: TEthereumAddress;
}

export interface ITokenNameRules {
  DepositTokenNamePrefix: string;
  StableDebtTokenNamePrefix: string;
  VariableDebtTokenNamePrefix: string;
  StakeTokenNamePrefix: string;

  SymbolPrefix: string;
  DepositSymbolPrefix: string;
  StableDebtSymbolPrefix: string;
  VariableDebtSymbolPrefix: string;
  StakeSymbolPrefix: string;

  RewardTokenName: string;
  RewardStakeTokenName: string;
  RewardTokenSymbol: string;
  RewardStakeTokenSymbol: string;
}

export interface IPrices {
  [token: string]: number | string;
}

export interface IDependencies {
  UniswapV2Router?: TEthereumAddress;
}

export const getParamPerNetwork = <T>(param: iParamsPerNetwork<T> | iParamsPerNetworkOpt<T>, network?: TNetwork): T =>
  param[getNetworkName(network)] as T;
