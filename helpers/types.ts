export interface SymbolMap<T> {
  [symbol: string]: T;
}

export type eNetwork = eEthereumNetwork | ePolygonNetwork;

export enum eEthereumNetwork {
  kovan = 'kovan',
  ropsten = 'ropsten',
  rinkeby = 'rinkeby',
  main = 'main',
  coverage = 'coverage',
  hardhat = 'hardhat',
}

export enum ePolygonNetwork {
  matic = 'matic',
  mumbai = 'mumbai',
}

export enum NetworkNames {
  kovan = 'kovan',
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

export type RecordOpt<K extends keyof any, T> = {
  [P in K]?: T;
};

export type PickOpt<T, K extends keyof T> = {
  [P in K]?: T[P];
};

export type OmitOpt<T, K extends keyof any> = PickOpt<T, Exclude<keyof T, K>>;

export const DefaultTokenSymbols: string[] = Object.keys(tokenSymbols);

export type iParamsPerNetwork<T> = iEthereumParamsPerNetwork<T> | iPolygonParamsPerNetwork<T>;

export interface iParamsPerNetworkAll<T> extends iEthereumParamsPerNetwork<T>, iPolygonParamsPerNetwork<T> {}

export interface iEthereumParamsPerNetwork<T> {
  [eEthereumNetwork.coverage]: T;
  [eEthereumNetwork.kovan]: T;
  [eEthereumNetwork.ropsten]: T;
  [eEthereumNetwork.rinkeby]: T;
  [eEthereumNetwork.main]: T;
  [eEthereumNetwork.hardhat]: T;
}

export interface iPolygonParamsPerNetwork<T> {
  [ePolygonNetwork.matic]: T;
  [ePolygonNetwork.mumbai]: T;
}

export interface IMocksConfig {
  UsdAddress: tEthereumAddress;
}

export interface IRuntimeConfig {
  MarketId: string;
  ProviderId: number;

  Names: ITokenNameRules;

  Mocks: IMocksConfig;

  ProviderRegistry: iParamsPerNetwork<tEthereumAddress>;
  ProviderRegistryOwner: iParamsPerNetwork<tEthereumAddress>;
  AddressProvider: iParamsPerNetwork<tEthereumAddress>;
  AddressProviderOwner: iParamsPerNetwork<tEthereumAddress>;

  ChainlinkAggregator: iParamsPerNetwork<ITokenAddress>;

  EmergencyAdmins: iParamsPerNetwork<tEthereumAddress[]>;

  Dependencies: iParamsPerNetwork<IDependencies>;
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
