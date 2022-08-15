// export type EAllNetworks = EEthereumNetwork | EPolygonNetwork | EOtherNetwork;
export type EHostLocalNetworks = EEthereumNetwork.hardhat | EEthereumNetwork.coverage;
// export type ENetwork = Exclude<EAllNetworks, EHostLocalNetworks>;

enum EEthereumNetwork {
  kovan = 'kovan',
  goerli = 'goerli',
  ropsten = 'ropsten',
  rinkeby = 'rinkeby',
  main = 'main',
  coverage = 'coverage',
  hardhat = 'hardhat',
}

enum EOtherNetwork {
  bsc = 'bsc',
  bsc_testnet = 'bsc_testnet',
  avalanche_testnet = 'avalanche_testnet',
  avalanche = 'avalanche',
  fantom_testnet = 'fantom_testnet',
  fantom = 'fantom',
}

enum EPolygonNetwork {
  matic = 'matic',
  mumbai = 'mumbai',
  arbitrum_testnet = 'arbitrum_testnet',
  arbitrum = 'arbitrum',
  optimistic_testnet = 'optimistic_testnet',
  optimistic = 'optimistic',
}

export const EAllNetworks = { ...EEthereumNetwork, ...EPolygonNetwork, ...EOtherNetwork };
export type EAllNetworks = typeof EAllNetworks;
export type ENetwork = keyof EAllNetworks;

export const isPolygonNetwork = (name: string): boolean => !!EPolygonNetwork[name];

export const isKnownNetworkName = (name: string): boolean =>
  Boolean(isPolygonNetwork(name) || EEthereumNetwork[name] || EOtherNetwork[name]);

export const isAutoGasNetwork = (name: string): boolean => isPolygonNetwork(name);
