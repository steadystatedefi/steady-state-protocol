import path from 'path';
import fs from 'fs';
import dotenv from 'dotenv';
import { HardhatUserConfig } from 'hardhat/types';
// @ts-ignore
import { accounts } from './helpers/test-wallets.js';
import { eEthereumNetwork, eNetwork, eOtherNetwork, ePolygonNetwork } from './helpers/types';
import { BUIDLEREVM_CHAINID, COVERAGE_CHAINID } from './helpers/buidler-constants';
import { NETWORKS_RPC_URL, NETWORKS_DEFAULT_GAS, FORK_RPC_URL } from './helper-hardhat-config';

import 'hardhat-tracer';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-gas-reporter';
import 'hardhat-typechain';
import '@tenderly/hardhat-tenderly';
import 'solidity-coverage';
import 'hardhat-abi-exporter';
import 'hardhat-contract-sizer';
import 'hardhat-tracer';
import 'hardhat-storage-layout';

dotenv.config();

const SKIP_LOAD = process.env.SKIP_LOAD === 'true';
const DEFAULT_BLOCK_GAS_LIMIT = 7000000;
const DEFAULT_GAS_MUL = 2;
const HARDFORK = 'istanbul';
const MNEMONIC_PATH = "m/44'/60'/0'/0";
const MNEMONIC = process.env.MNEMONIC || '';
const BSC_FORK_URL = process.env.BSC_FORK_URL || '';
const FORK = process.env.FORK;
const IS_FORK = FORK ? true : false;

const KEY_SEL = process.env.KEY_SEL || '';

const keySelector = (keyName: string) => {
  return (KEY_SEL != '' ? process.env[`${keyName}_${KEY_SEL}`] : undefined) || process.env[keyName];
};

const ETHERSCAN_KEY = keySelector('ETHERSCAN_KEY') || '';
const COINMARKETCAP_KEY = keySelector('COINMARKETCAP_KEY') || '';
const MNEMONIC_MAIN = IS_FORK ? MNEMONIC : keySelector('MNEMONIC_MAIN') || MNEMONIC;


// Prevent to load scripts before compilation and typechain
if (!SKIP_LOAD) {
  ['tools', 'migrations', 'deploy', 'deploy/dev', 'deploy/full', 'subtasks'].forEach(
    (folder) => {
      const tasksPath = path.join(__dirname, 'tasks', folder);
      fs.readdirSync(tasksPath)
        .filter((pth) => pth.includes('.ts'))
        .forEach((task) => {
          require(`${tasksPath}/${task}`);
        });
    }
  );
}

require(path.join(__dirname, 'tasks/subtasks', 'set-dre.ts'));

const getCommonNetworkConfig = (networkName: eNetwork, networkId: number, mnemonic?: string) => ({
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

const FORK_URLS: Record<eNetwork, string> = {
  [eOtherNetwork.bsc]: BSC_FORK_URL,
  [eOtherNetwork.bsc_testnet]: '',
  [eOtherNetwork.avalanche]: FORK_RPC_URL[eOtherNetwork.avalanche] || '',
  [eOtherNetwork.avalanche_testnet]: '',
  [eOtherNetwork.fantom]: '',
  [eOtherNetwork.fantom_testnet]: '',
  [eEthereumNetwork.kovan]: '',
  [eEthereumNetwork.ropsten]: '',
  [eEthereumNetwork.rinkeby]: '',
  [eEthereumNetwork.main]: '',
  [eEthereumNetwork.coverage]: '',
  [eEthereumNetwork.hardhat]: '',
  [ePolygonNetwork.matic]: '',
  [ePolygonNetwork.mumbai]: '',
  [ePolygonNetwork.arbitrum_testnet]: '',
  [ePolygonNetwork.arbitrum]: '',
  [ePolygonNetwork.optimistic_testnet]: '',
  [ePolygonNetwork.optimistic]: '',
};

const getForkConfig = (name: eNetwork) => ({
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
  let url = NETWORKS_RPC_URL[FORK];
  if (!url) {
    throw new Error('Unknown network to fork: ' + FORK);
  }
  if (FORK_RPC_URL[FORK]) {
    url = FORK_RPC_URL[FORK];
  } else if (FORK == eOtherNetwork.bsc) {
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
    blockNumber: blockNumbers[FORK],
    url: url,
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
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
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
    forkNetwork: '1', //Network id of the network we want to fork
  },
  networks: {
    coverage: {
      url: 'http://localhost:8555',
      chainId: COVERAGE_CHAINID,
    },
    bsc_fork: getForkConfig(eOtherNetwork.bsc),
    avalanche_fork: getForkConfig(eOtherNetwork.avalanche),
    avalanche_testnet_fork: getForkConfig(eOtherNetwork.avalanche_testnet),

    kovan: getCommonNetworkConfig(eEthereumNetwork.kovan, 42),
    ropsten: getCommonNetworkConfig(eEthereumNetwork.ropsten, 3),
    rinkeby: getCommonNetworkConfig(eEthereumNetwork.rinkeby, 4),
    main: getCommonNetworkConfig(eEthereumNetwork.main, 1, MNEMONIC_MAIN),
    bsc_testnet: getCommonNetworkConfig(eOtherNetwork.bsc_testnet, 97),
    bsc: getCommonNetworkConfig(eOtherNetwork.bsc, 56, MNEMONIC_MAIN),
    avalanche_testnet: getCommonNetworkConfig(eOtherNetwork.avalanche_testnet, 43113),
    avalanche: getCommonNetworkConfig(eOtherNetwork.avalanche, 43114, MNEMONIC_MAIN),
    fantom_testnet: getCommonNetworkConfig(eOtherNetwork.fantom_testnet, 4002),
    fantom: getCommonNetworkConfig(eOtherNetwork.fantom, 250, MNEMONIC_MAIN),
    arbitrum_testnet: getCommonNetworkConfig(ePolygonNetwork.arbitrum_testnet, 421611),
    arbitrum: getCommonNetworkConfig(ePolygonNetwork.arbitrum, 42161, MNEMONIC_MAIN),
    optimistic_testnet: getCommonNetworkConfig(ePolygonNetwork.optimistic_testnet, 69),
    optimistic: getCommonNetworkConfig(ePolygonNetwork.optimistic, 10, MNEMONIC_MAIN),
    matic: getCommonNetworkConfig(ePolygonNetwork.matic, 137, MNEMONIC_MAIN),
    mumbai: getCommonNetworkConfig(ePolygonNetwork.mumbai, 80001),
    hardhat: {
      hardfork: HARDFORK,
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      gas: DEFAULT_BLOCK_GAS_LIMIT,
      gasPrice: 8000000000,
      chainId: BUIDLEREVM_CHAINID,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      accounts: accounts.map(({ secretKey, balance }: { secretKey: string; balance: string }) => ({
        privateKey: secretKey,
        balance,
      })),
      forking: mainnetFork(),
    },
  },
};

export default buidlerConfig;