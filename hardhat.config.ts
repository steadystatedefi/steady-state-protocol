import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@tenderly/hardhat-tenderly';
import '@typechain/hardhat';
import dotenv from 'dotenv';
import 'hardhat-abi-exporter';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'hardhat-tracer';
import { HardhatUserConfig } from 'hardhat/types';
import 'solidity-coverage';

import fs from 'fs';
import path from 'path';

import { NETWORKS_RPC_URL, NETWORKS_DEFAULT_GAS, FORK_RPC_URL } from './helper-hardhat-config';
import { BUIDLEREVM_CHAINID, COVERAGE_CHAINID } from './helpers/buidler-constants';
import testWalletsData from './helpers/test-wallets.json';
import { EEthereumNetwork, TNetwork, EOtherNetwork, EPolygonNetwork } from './helpers/types';
import './tasks/subtasks/set-dre';

dotenv.config();

const SKIP_LOAD = process.env.SKIP_LOAD === 'true';
const DEFAULT_BLOCK_GAS_LIMIT = 7000000;
const DEFAULT_GAS_MUL = 2;
const HARDFORK = 'istanbul';
const MNEMONIC_PATH = "m/44'/60'/0'/0";
const MNEMONIC = process.env.MNEMONIC || '';
const BSC_FORK_URL = process.env.BSC_FORK_URL || '';
const { FORK } = process.env;
const IS_FORK = !!FORK;

const KEY_SEL = process.env.KEY_SEL || '';

const keySelector = (keyName: string) =>
  (KEY_SEL !== '' ? process.env[`${keyName}_${KEY_SEL}`] : undefined) || process.env[keyName];

const ETHERSCAN_KEY = keySelector('ETHERSCAN_KEY') || '';
const COINMARKETCAP_KEY = keySelector('COINMARKETCAP_KEY') || '';
const MNEMONIC_MAIN = IS_FORK ? MNEMONIC : keySelector('MNEMONIC_MAIN') || MNEMONIC;

// Prevent to load scripts before compilation and typechain
if (!SKIP_LOAD) {
  ['tools', 'migrations', 'deploy', 'deploy/dev', 'deploy/full', 'subtasks'].forEach((folder) => {
    const tasksPath = path.join(__dirname, 'tasks', folder);
    fs.readdirSync(tasksPath)
      .filter((pth) => pth.includes('.ts'))
      .forEach((task) => {
        import(`${tasksPath}/${task}`);
      });
  });
}

const getCommonNetworkConfig = (networkName: TNetwork, networkId: number, mnemonic?: string) => ({
  url: NETWORKS_RPC_URL[networkName],
  hardfork: HARDFORK,
  blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
  gasMultiplier: DEFAULT_GAS_MUL,
  gasPrice: NETWORKS_DEFAULT_GAS[networkName],
  chainId: networkId,
  accounts: {
    mnemonic: mnemonic || MNEMONIC,
    path: MNEMONIC_PATH,
    initialIndex: 0,
    count: 20,
  },
});

const FORK_URLS: Record<TNetwork, string> = {
  [EOtherNetwork.bsc]: BSC_FORK_URL,
  [EOtherNetwork.bsc_testnet]: '',
  [EOtherNetwork.avalanche]: FORK_RPC_URL[EOtherNetwork.avalanche] || '',
  [EOtherNetwork.avalanche_testnet]: '',
  [EOtherNetwork.fantom]: '',
  [EOtherNetwork.fantom_testnet]: '',
  [EEthereumNetwork.kovan]: '',
  [EEthereumNetwork.ropsten]: '',
  [EEthereumNetwork.rinkeby]: '',
  [EEthereumNetwork.main]: '',
  [EEthereumNetwork.coverage]: '',
  [EEthereumNetwork.hardhat]: '',
  [EPolygonNetwork.matic]: '',
  [EPolygonNetwork.mumbai]: '',
  [EPolygonNetwork.arbitrum_testnet]: '',
  [EPolygonNetwork.arbitrum]: '',
  [EPolygonNetwork.optimistic_testnet]: '',
  [EPolygonNetwork.optimistic]: '',
};

const getForkConfig = (name: TNetwork) => ({
  url: FORK_URLS[name] ?? '',
  accounts: {
    mnemonic: MNEMONIC,
    path: MNEMONIC_PATH,
  },
});

const mainnetFork = () => {
  if (!FORK) {
    return undefined;
  }
  let url = NETWORKS_RPC_URL[FORK] as string;
  if (!url) {
    throw new Error(`Unknown network to fork: ${FORK}`);
  }
  if (FORK_RPC_URL[FORK]) {
    url = FORK_RPC_URL[FORK] as string;
  } else if (FORK === EOtherNetwork.bsc) {
    console.log('==================================================================================');
    console.log('==================================================================================');
    console.log('WARNING!  Forking of BSC requires a 3rd party provider or a special workaround');
    console.log('See here: https://github.com/nomiclabs/hardhat/issues/1236');
    console.log('==================================================================================');
    console.log('==================================================================================');
  }

  const blockNumbers = {
    // [eEthereumNetwork.main]: 13283829, // 12914827
  };

  return {
    blockNumber: blockNumbers[FORK] as number | undefined,
    url,
  };
};

const buidlerConfig: HardhatUserConfig = {
  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
    spacing: 2,
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 120,
    coinmarketcap: COINMARKETCAP_KEY,
  },
  solidity: {
    compilers: [
      {
        version: '0.8.10',
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: 'istanbul',
        },
      },
    ],
  },
  typechain: {
    outDir: './types',
    target: 'ethers-v5',
  },
  etherscan: {
    apiKey: ETHERSCAN_KEY,
  },
  mocha: {
    timeout: 0,
  },
  tenderly: {
    project: process.env.TENDERLY_PROJECT || '',
    username: process.env.TENDERLY_USERNAME || '',
    forkNetwork: '1', // Network id of the network we want to fork
  },
  networks: {
    coverage: {
      url: 'http://localhost:8555',
      chainId: COVERAGE_CHAINID,
    },
    bsc_fork: getForkConfig(EOtherNetwork.bsc),
    avalanche_fork: getForkConfig(EOtherNetwork.avalanche),
    avalanche_testnet_fork: getForkConfig(EOtherNetwork.avalanche_testnet),

    kovan: getCommonNetworkConfig(EEthereumNetwork.kovan, 42),
    ropsten: getCommonNetworkConfig(EEthereumNetwork.ropsten, 3),
    rinkeby: getCommonNetworkConfig(EEthereumNetwork.rinkeby, 4),
    main: getCommonNetworkConfig(EEthereumNetwork.main, 1, MNEMONIC_MAIN),
    bsc_testnet: getCommonNetworkConfig(EOtherNetwork.bsc_testnet, 97),
    bsc: getCommonNetworkConfig(EOtherNetwork.bsc, 56, MNEMONIC_MAIN),
    avalanche_testnet: getCommonNetworkConfig(EOtherNetwork.avalanche_testnet, 43113),
    avalanche: getCommonNetworkConfig(EOtherNetwork.avalanche, 43114, MNEMONIC_MAIN),
    fantom_testnet: getCommonNetworkConfig(EOtherNetwork.fantom_testnet, 4002),
    fantom: getCommonNetworkConfig(EOtherNetwork.fantom, 250, MNEMONIC_MAIN),
    arbitrum_testnet: getCommonNetworkConfig(EPolygonNetwork.arbitrum_testnet, 421611),
    arbitrum: getCommonNetworkConfig(EPolygonNetwork.arbitrum, 42161, MNEMONIC_MAIN),
    optimistic_testnet: getCommonNetworkConfig(EPolygonNetwork.optimistic_testnet, 69),
    optimistic: getCommonNetworkConfig(EPolygonNetwork.optimistic, 10, MNEMONIC_MAIN),
    matic: getCommonNetworkConfig(EPolygonNetwork.matic, 137, MNEMONIC_MAIN),
    mumbai: getCommonNetworkConfig(EPolygonNetwork.mumbai, 80001),
    hardhat: {
      hardfork: HARDFORK,
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      gas: DEFAULT_BLOCK_GAS_LIMIT,
      gasPrice: 8000000000,
      chainId: BUIDLEREVM_CHAINID,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      accounts: testWalletsData.accounts.map(({ secretKey, balance }: { secretKey: string; balance: string }) => ({
        privateKey: secretKey,
        balance,
      })),
      forking: mainnetFork(),
    },
  },
};

export default buidlerConfig;
