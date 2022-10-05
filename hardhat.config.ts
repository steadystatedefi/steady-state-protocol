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

import { NETWORKS_RPC_URL, NETWORKS_DEFAULT_GAS, FORK_URL } from './helper-hardhat-config';
import { BUIDLEREVM_CHAINID, COVERAGE_CHAINID } from './helpers/buidler-constants';
import { EAllNetworks, ENetwork } from './helpers/config-networks';
import testWalletsData from './helpers/test-wallets.json';
import './tasks/plugins/set-dre';
import './tasks/plugins/storage-layout';

dotenv.config();

const SKIP_LOAD = process.env.SKIP_LOAD === 'true';
const DEFAULT_BLOCK_GAS_LIMIT = 7000000;
const DEFAULT_GAS_MUL = 2;
const HARDFORK = 'istanbul';
const MNEMONIC_PATH = "m/44'/60'/0'/0";
const MNEMONIC = process.env.MNEMONIC ?? '';
const [FORK, FORK_BLOCK] = (process.env.FORK ?? '').split('@', 2);
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
    if (fs.existsSync(tasksPath)) {
      fs.readdirSync(tasksPath)
        .filter((pth) => pth.includes('.ts'))
        .forEach((task) => {
          import(`${tasksPath}/${task}`);
        });
    }
  });
}

const getCommonNetworkConfig = (networkName: ENetwork, networkId: number, mnemonic?: string) => ({
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

const getForkConfig = (name: ENetwork) => ({
  url: FORK_URL[name] ?? '',
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
  if (FORK_URL[FORK]) {
    url = FORK_URL[FORK] as string;
  } else if (FORK in FORK_URL) {
    console.log('==================================================================================');
    console.log('==================================================================================');
    console.log('WARNING!  Forking requires a 3rd party provider or a special workaround');
    console.log('See here: https://github.com/nomiclabs/hardhat/issues/1236');
    console.log('==================================================================================');
    console.log('==================================================================================');
  }

  const blockNumbers: Record<string, number> = {
    // [EAllNetworks.main]: 13283829, // 12914827
  };

  const forkBlock = parseInt(FORK_BLOCK, 10);

  return {
    blockNumber: Number.isNaN(forkBlock) ? blockNumbers[FORK] : forkBlock,
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
    bsc_fork: getForkConfig(EAllNetworks.bsc),
    avalanche_fork: getForkConfig(EAllNetworks.avalanche),
    avalanche_testnet_fork: getForkConfig(EAllNetworks.avalanche_testnet),

    kovan: getCommonNetworkConfig(EAllNetworks.kovan, 42),
    goerli: getCommonNetworkConfig(EAllNetworks.goerli, 5),
    ropsten: getCommonNetworkConfig(EAllNetworks.ropsten, 3),
    rinkeby: getCommonNetworkConfig(EAllNetworks.rinkeby, 4),
    main: getCommonNetworkConfig(EAllNetworks.main, 1, MNEMONIC_MAIN),
    bsc_testnet: getCommonNetworkConfig(EAllNetworks.bsc_testnet, 97),
    bsc: getCommonNetworkConfig(EAllNetworks.bsc, 56, MNEMONIC_MAIN),
    avalanche_testnet: getCommonNetworkConfig(EAllNetworks.avalanche_testnet, 43113),
    avalanche: getCommonNetworkConfig(EAllNetworks.avalanche, 43114, MNEMONIC_MAIN),
    fantom_testnet: getCommonNetworkConfig(EAllNetworks.fantom_testnet, 4002),
    fantom: getCommonNetworkConfig(EAllNetworks.fantom, 250, MNEMONIC_MAIN),
    arbitrum_testnet: getCommonNetworkConfig(EAllNetworks.arbitrum_testnet, 421611),
    arbitrum: getCommonNetworkConfig(EAllNetworks.arbitrum, 42161, MNEMONIC_MAIN),
    optimistic_testnet: getCommonNetworkConfig(EAllNetworks.optimistic_testnet, 69),
    optimistic: getCommonNetworkConfig(EAllNetworks.optimistic, 10, MNEMONIC_MAIN),
    matic: getCommonNetworkConfig(EAllNetworks.matic, 137, MNEMONIC_MAIN),
    mumbai: getCommonNetworkConfig(EAllNetworks.mumbai, 80001),
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
