import dotenv from 'dotenv';

import { ENetwork } from './helpers/config-networks';

dotenv.config();

const INFURA_KEY = process.env.INFURA_KEY ?? '';
const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? '';
const MORALIS_KEY = process.env.MORALIS_KEY ?? '';
const BSC_FORK_URL = process.env.BSC_FORK_URL ?? '';

const GWEI = 1000 * 1000 * 1000;

type PerNetworkValue<T = string> = Record<ENetwork, T>;

export const NETWORKS_RPC_URL: PerNetworkValue = {
  kovan: ALCHEMY_KEY ? `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_KEY}` : `https://kovan.infura.io/v3/${INFURA_KEY}`,
  goerli: ALCHEMY_KEY
    ? `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_KEY}`
    : `https://goerli.infura.io/v3/${INFURA_KEY}`,
  ropsten: ALCHEMY_KEY
    ? `https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://ropsten.infura.io/v3/${INFURA_KEY}`,
  rinkeby: ALCHEMY_KEY
    ? `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://rinkeby.infura.io/v3/${INFURA_KEY}`,
  main: ALCHEMY_KEY
    ? `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://mainnet.infura.io/v3/${INFURA_KEY}`,
  coverage: 'http://localhost:8555',
  hardhat: 'http://localhost:8545',
  bsc_testnet: 'https://data-seed-prebsc-1-s2.binance.org:8545/',
  bsc: 'https://bsc-dataseed.binance.org/',
  avalanche_testnet: 'https://api.avax-test.network/ext/bc/C/rpc',
  avalanche: MORALIS_KEY
    ? `https://speedy-nodes-nyc.moralis.io/${MORALIS_KEY}/avalanche/mainnet`
    : 'https://api.avax.network/ext/bc/C/rpc',
  fantom_testnet: 'https://rpc.testnet.fantom.network/',
  fantom: 'https://rpcapi.fantom.network/',
  arbitrum_testnet: 'https://rinkeby.arbitrum.io/rpc',
  arbitrum: 'https://arb1.arbitrum.io/rpc',
  optimistic_testnet: 'https://kovan.optimism.io',
  optimistic: 'https://mainnet.optimism.io',
  mumbai: 'https://rpc-mumbai.maticvigil.com',
  matic: 'https://rpc-mainnet.matic.network',
};

const gasPrice = (def: number) => (process.env.GAS_PRICE ? parseInt(process.env.GAS_PRICE, 10) : def) * GWEI;

export const NETWORKS_DEFAULT_GAS: Partial<PerNetworkValue<number | 'auto'>> = {
  kovan: gasPrice(1),
  goerli: gasPrice(1),
  ropsten: gasPrice(10),
  rinkeby: gasPrice(1),
  main: gasPrice(85),
  coverage: gasPrice(65),
  hardhat: gasPrice(25),
  bsc_testnet: gasPrice(10),
  bsc: gasPrice(1),
  avalanche_testnet: gasPrice(30),
  avalanche: gasPrice(25),
  fantom_testnet: gasPrice(10),
  fantom: gasPrice(1),
  arbitrum_testnet: 'auto',
  arbitrum: 'auto',
  optimistic_testnet: 'auto',
  optimistic: 'auto',
  mumbai: gasPrice(1),
  matic: gasPrice(2),
};

const FORK_RPC_URL: Partial<PerNetworkValue> = {
  bsc: MORALIS_KEY ? `https://speedy-nodes-nyc.moralis.io/${MORALIS_KEY}/bsc/mainnet/archive` : undefined,
  avalanche: MORALIS_KEY
    ? `https://speedy-nodes-nyc.moralis.io/${MORALIS_KEY}/avalanche/mainnet`
    : 'https://api.avax.network/ext/bc/C/rpc',
};

export const FORK_URL: Partial<PerNetworkValue> = {
  bsc: BSC_FORK_URL || FORK_RPC_URL.bsc,
  avalanche: FORK_RPC_URL.avalanche,
};
