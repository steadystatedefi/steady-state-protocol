export const TEST_SNAPSHOT_ID = '0x1';
export const EVM_CHAINID = 31337;
export const COV_CHAINID = 1337;
export const GWEI = 1000 * 1000 * 1000;

export const SKIP_LOAD = process.env.SKIP_LOAD == 'true';
export const MAINNET_FORK = process.env.MAINNET_FORK == 'true';

require('dotenv').config();

export const DEFAULT_BLOCK_GAS_LIMIT = 7000000;
export const DEFAULT_GAS_MUL = 2;
export const HARDFORK = 'istanbul';
export const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY || '';
export const MNEMONIC_PATH = "m/44'/60'/0'/0";
export const MNEMONIC = process.env.MNEMONIC || '';
export const COINMARKETCAP_KEY = process.env.COINMARKETCAP_KEY || '';
export const INFURA_KEY = process.env.INFURA_KEY || '';
export const ALCHEMY_KEY = process.env.ALCHEMY_KEY || '';