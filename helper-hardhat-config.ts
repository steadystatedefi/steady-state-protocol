import dotenv from 'dotenv';

import {
  EEthereumNetwork,
  EOtherNetwork,
  EPolygonNetwork,
  iParamsPerNetwork,
  iParamsPerNetworkOpt,
} from './helpers/types';

dotenv.config();

const INFURA_KEY = process.env.INFURA_KEY || '';
const ALCHEMY_KEY = process.env.ALCHEMY_KEY || '';
const MORALIS_KEY = process.env.MORALIS_KEY || '';

const GWEI = 1000 * 1000 * 1000;

export const NETWORKS_RPC_URL: iParamsPerNetwork<string> = {
  [EEthereumNetwork.kovan]: ALCHEMY_KEY
    ? `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://kovan.infura.io/v3/${INFURA_KEY}`,
  [EEthereumNetwork.ropsten]: ALCHEMY_KEY
    ? `https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://ropsten.infura.io/v3/${INFURA_KEY}`,
  [EEthereumNetwork.rinkeby]: ALCHEMY_KEY
    ? `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://rinkeby.infura.io/v3/${INFURA_KEY}`,
  [EEthereumNetwork.main]: ALCHEMY_KEY
    ? `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://mainnet.infura.io/v3/${INFURA_KEY}`,
  [EEthereumNetwork.coverage]: 'http://localhost:8555',
  [EEthereumNetwork.hardhat]: 'http://localhost:8545',
  [EOtherNetwork.bsc_testnet]: 'https://data-seed-prebsc-1-s2.binance.org:8545/',
  [EOtherNetwork.bsc]: 'https://bsc-dataseed.binance.org/',
  [EOtherNetwork.avalanche_testnet]: 'https://api.avax-test.network/ext/bc/C/rpc',
  [EOtherNetwork.avalanche]: MORALIS_KEY
    ? `https://speedy-nodes-nyc.moralis.io/${MORALIS_KEY}/avalanche/mainnet`
    : 'https://api.avax.network/ext/bc/C/rpc',
  [EOtherNetwork.fantom_testnet]: 'https://rpc.testnet.fantom.network/',
  [EOtherNetwork.fantom]: 'https://rpcapi.fantom.network/',
  [EPolygonNetwork.arbitrum_testnet]: 'https://rinkeby.arbitrum.io/rpc',
  [EPolygonNetwork.arbitrum]: 'https://arb1.arbitrum.io/rpc',
  [EPolygonNetwork.optimistic_testnet]: 'https://kovan.optimism.io',
  [EPolygonNetwork.optimistic]: 'https://mainnet.optimism.io',
  [EPolygonNetwork.mumbai]: 'https://rpc-mumbai.maticvigil.com',
  [EPolygonNetwork.matic]: 'https://rpc-mainnet.matic.network',
};

export const FORK_RPC_URL: iParamsPerNetworkOpt<string> = {
  [EOtherNetwork.bsc]: MORALIS_KEY
    ? `https://speedy-nodes-nyc.moralis.io/${MORALIS_KEY}/bsc/mainnet/archive`
    : undefined,
  [EOtherNetwork.avalanche]: MORALIS_KEY
    ? `https://speedy-nodes-nyc.moralis.io/${MORALIS_KEY}/avalanche/mainnet`
    : 'https://api.avax.network/ext/bc/C/rpc',
};

const gasPrice = (def: number) => (process.env.GAS_PRICE ? parseInt(process.env.GAS_PRICE, 10) : def) * GWEI;

export const NETWORKS_DEFAULT_GAS: iParamsPerNetwork<number | 'auto'> = {
  [EEthereumNetwork.kovan]: gasPrice(1),
  [EEthereumNetwork.ropsten]: gasPrice(10),
  [EEthereumNetwork.rinkeby]: gasPrice(1),
  [EEthereumNetwork.main]: gasPrice(85),
  [EEthereumNetwork.coverage]: gasPrice(65),
  [EEthereumNetwork.hardhat]: gasPrice(25),
  [EOtherNetwork.bsc_testnet]: gasPrice(10),
  [EOtherNetwork.bsc]: gasPrice(1),
  [EOtherNetwork.avalanche_testnet]: gasPrice(30),
  [EOtherNetwork.avalanche]: gasPrice(25),
  [EOtherNetwork.fantom_testnet]: gasPrice(10),
  [EOtherNetwork.fantom]: gasPrice(1),
  [EPolygonNetwork.arbitrum_testnet]: 'auto',
  [EPolygonNetwork.arbitrum]: 'auto',
  [EPolygonNetwork.optimistic_testnet]: 'auto',
  [EPolygonNetwork.optimistic]: 'auto',
  [EPolygonNetwork.mumbai]: gasPrice(1),
  [EPolygonNetwork.matic]: gasPrice(2),
};
