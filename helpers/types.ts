import { getNetworkName } from './runtime-utils';

export interface SymbolMap<T> {
  [symbol: string]: T;
}

export type eNetwork = eEthereumNetwork | ePolygonNetwork | eOtherNetwork;

export enum eEthereumNetwork {
  kovan = 'kovan',
  goerli = 'goerli',
  ropsten = 'ropsten',
  rinkeby = 'rinkeby',
  main = 'main',
  coverage = 'coverage',
  hardhat = 'hardhat',
}

export enum eOtherNetwork {
  bsc = 'bsc',
  bsc_testnet = 'bsc_testnet',
  avalanche_testnet = 'avalanche_testnet',
  avalanche = 'avalanche',
  fantom_testnet = 'fantom_testnet',
  fantom = 'fantom',
}

export enum ePolygonNetwork {
  matic = 'matic',
  mumbai = 'mumbai',
  arbitrum_testnet = 'arbitrum_testnet',
  arbitrum = 'arbitrum',
  optimistic_testnet = 'optimistic_testnet',
  optimistic = 'optimistic',
}

export const isPolygonNetwork = (name: string): boolean => ePolygonNetwork[name] !== undefined;

export const isKnownNetworkName = (name: string): boolean =>
  isPolygonNetwork(name) || eEthereumNetwork[name] !== undefined || eOtherNetwork[name] !== undefined;

export const isAutoGasNetwork = (name: string): boolean => isPolygonNetwork(name);

export enum NetworkNames {
  kovan = 'kovan',
  goerli = 'goerli',
  ropsten = 'ropsten',
  rinkeby = 'rinkeby',
  main = 'main',
  matic = 'matic',
  mumbai = 'mumbai',
}

export type tEthereumAddress = string;

export interface iAssetCommon<T> {
  [key: string]: T;
}

export interface iAssetBase<T> {
  WETH: T;
  DAI: T;
  USDC: T;
  USDT: T;
  WBTC: T;
  USD: T;
}

const tokenSymbols: iAssetBase<string> = {
  WETH: '',
  DAI: '',
  USDC: '',
  USDT: '',
  WBTC: '',
  USD: '',
};

export type iAssetsWithoutUSD<T> = Omit<iAssetBase<T>, 'USD'>;
export type iAssetsWithoutUSDOpt<T> = OmitOpt<iAssetBase<T>, 'USD'>;

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
  [eEthereumNetwork.coverage]: T;
  [eEthereumNetwork.kovan]: T;
  [eEthereumNetwork.goerli]: T;
  [eEthereumNetwork.ropsten]: T;
  [eEthereumNetwork.rinkeby]: T;
  [eEthereumNetwork.main]: T;
  [eEthereumNetwork.hardhat]: T;
}

export interface iPolygonParamsPerNetwork<T> {
  [ePolygonNetwork.matic]: T;
  [ePolygonNetwork.mumbai]: T;
  [ePolygonNetwork.arbitrum_testnet]: T;
  [ePolygonNetwork.arbitrum]: T;
  [ePolygonNetwork.optimistic_testnet]: T;
  [ePolygonNetwork.optimistic]: T;
}

export interface iParamsPerOtherNetwork<T> {
  [eOtherNetwork.bsc]: T;
  [eOtherNetwork.bsc_testnet]: T;
  [eOtherNetwork.avalanche]: T;
  [eOtherNetwork.avalanche_testnet]: T;
  [eOtherNetwork.fantom]: T;
  [eOtherNetwork.fantom_testnet]: T;
}

export interface IMocksConfig {
  UsdAddress: tEthereumAddress;
}

export interface IConfiguration {
  Owner: iParamsPerNetworkOpt<tEthereumAddress>;
  DepositTokens: iParamsPerNetworkOpt<SymbolMap<string>>;
}

export interface ITokenAddress {
  [token: string]: tEthereumAddress;
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
  UniswapV2Router?: tEthereumAddress;
}

export enum EContractId {
  AccessController = 'AccessController',
  ApprovalCatalog = 'ApprovalCatalog',
  ApprovalCatalogV1 = 'ApprovalCatalogV1',
  ProxyCatalog = 'ProxyCatalog',
  InsuredPool = 'InsuredPool',
  InsuredPoolV1 = 'InsuredPoolV1',
  CollateralCurrency = 'CollateralCurrency',
}

export const getParamPerNetwork = <T>(param: iParamsPerNetwork<T> | iParamsPerNetworkOpt<T>, network?: eNetwork): T =>
  param[getNetworkName(network)] as T;
