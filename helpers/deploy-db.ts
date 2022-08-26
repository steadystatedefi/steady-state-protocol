import { Contract } from 'ethers';
import low from 'lowdb';
import FileSync from 'lowdb/adapters/FileSync';

import { stringifyArgs } from './contract-verification';
import { DRE } from './dre';
import { isForkNetwork, notFalsyOrZeroAddress } from './runtime-utils';
import { EthereumAddress } from './types';

const getDb = () => low(new FileSync('./deployed-contracts.json'));

export interface DbNamedEntry {
  address: EthereumAddress;
  count: number;
}

export interface DbInstanceEntry {
  id: string;
  factory: string;
  needsSync?: boolean;
  verify?: {
    args?: string;
    impl?: string;
    subType?: string;
  };
}

export const cleanupJsonDb = (currentNetwork: string): void => {
  getDb().set(`${currentNetwork}`, {}).write();
};

export const addContractToJsonDb = (
  contractId: string,
  contractInstance: Contract,
  contractAddr: string,
  register: boolean,
  verifyArgs?: unknown[]
): void => {
  const currentNetwork = DRE.network.name;

  if (isForkNetwork() || (currentNetwork !== 'hardhat' && !currentNetwork.includes('coverage'))) {
    console.log(`*** ${contractId} ***\n`);
    console.log(`Network: ${currentNetwork}`);
    console.log(`contract address: ${contractInstance.address}`);

    if (contractInstance.deployTransaction) {
      console.log(`tx: ${contractInstance.deployTransaction.hash}`);
      console.log(`deployer address: ${contractInstance.deployTransaction.from}`);
      console.log(`gas price: ${contractInstance.deployTransaction.gasPrice?.toString() ?? ''}`);
      console.log(`gas used: ${contractInstance.deployTransaction.gasLimit?.toString()}`);
    }

    console.log(`\n******`);
    console.log();
  }

  addContractAddrToJsonDb(contractId, contractInstance.address, contractAddr, register, verifyArgs);
};

export function addContractAddrToJsonDb(
  contractId: string,
  contractAddr: string,
  contractFactory: string,
  register: boolean,
  verifyArgs?: unknown[]
): void {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  const logEntry: DbInstanceEntry = {
    id: contractId,
    factory: contractFactory,
  };

  if (verifyArgs !== undefined) {
    logEntry.verify = {
      args: stringifyArgs(verifyArgs),
    };
  }

  db.set(`${currentNetwork}.instance.${contractAddr}`, logEntry).write();

  if (register) {
    const node = `${currentNetwork}.named.${contractId}`;
    const value = db.get(node).value() as { count: number } | undefined;
    const count = value?.count ?? 0;
    const namedEntry: DbNamedEntry = {
      address: contractAddr,
      count: count + 1,
    };

    db.set(`${currentNetwork}.named.${contractId}`, namedEntry).write();
  }
}

export const addProxyToJsonDb = (
  id: string,
  proxyAddress: EthereumAddress,
  implAddress: EthereumAddress,
  subType: string,
  contractFactory: string,
  verifyArgs?: unknown[]
): void => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  const logEntry: DbInstanceEntry = {
    id,
    factory: contractFactory,
    verify: {
      impl: implAddress,
      subType,
    },
  };

  if (verifyArgs !== undefined) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    logEntry.verify!.args = stringifyArgs(verifyArgs);
  }

  db.set(`${currentNetwork}.external.${proxyAddress}`, logEntry).write();
};

const setNeedsSync = (section: string, contractAddr: EthereumAddress, needsSync: boolean): void => {
  const db = getDb();
  const path = `${DRE.network.name}.${section}.${contractAddr}`;
  const entry = db.get(path).value() as DbInstanceEntry;

  if (!entry?.id) {
    throw new Error(`Unknown ${section}: ${contractAddr}`);
  }
  entry.needsSync = needsSync;
  db.set(path, entry).write();
};

const isSyncNeeded = (section: string, contractAddr: EthereumAddress): boolean => {
  const db = getDb();
  const path = `${DRE.network.name}.${section}.${contractAddr}`;
  const entry = db.get(path).value() as DbInstanceEntry;

  if (!entry?.id) {
    throw new Error(`Unknown ${section}: ${contractAddr}`);
  }
  return !!entry.needsSync;
};

export const setInstanceNeedsSync = (contractAddr: EthereumAddress, needsSync: boolean): void =>
  setNeedsSync('instance', contractAddr, needsSync);

export const setExternalNeedsSync = (contractAddr: EthereumAddress, needsSync: boolean): void =>
  setNeedsSync('external', contractAddr, needsSync);

export const isInstanceNeedsSync = (contractAddr: EthereumAddress): boolean => isSyncNeeded('instance', contractAddr);

export const isExternalNeedsSync = (contractAddr: EthereumAddress): boolean => isSyncNeeded('external', contractAddr);

export const addExternalToJsonDb = (
  id: string,
  address: EthereumAddress,
  contractFactory: string,
  verifyArgs?: unknown[]
): void => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  const logEntry: DbInstanceEntry = {
    id,
    factory: contractFactory,
    verify: {},
  };

  if (verifyArgs !== undefined) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    logEntry.verify!.args = stringifyArgs(verifyArgs);
  }

  db.set(`${currentNetwork}.external.${address}`, logEntry).write();
};

export const addNamedToJsonDb = (contractId: string, contractAddress: EthereumAddress): void => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  const node = `${currentNetwork}.named.${contractId}`;
  const nodeValue = db.get(node).value() as { count: number } | undefined;

  db.set(`${currentNetwork}.named.${contractId}`, {
    address: contractAddress,
    count: 1 + (nodeValue?.count || 0),
  }).write();
};

export const setVerifiedToJsonDb = (address: EthereumAddress, verified: boolean): void => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  db.set(`${currentNetwork}.verified.${address}`, verified).write();
};

export const getVerifiedFromJsonDb = (address: EthereumAddress): Promise<boolean> => {
  const currentNetwork = DRE.network.name;
  const db = getDb();
  return db.get(`${currentNetwork}.verified.${address}`).value() as Promise<boolean>;
};

export const getInstanceFromJsonDb = (address: EthereumAddress): DbInstanceEntry =>
  <DbInstanceEntry>getDb().get(`${DRE.network.name}.instance.${address}`).value();

export const getInstancesFromJsonDb = (): [string, DbInstanceEntry][] => {
  const db = getDb();
  const collection = db.get(`${DRE.network.name}.instance`);
  const value = collection.value() as DbInstanceEntry[] | undefined;

  return Object.entries<DbInstanceEntry>(value || []);
};

export const getExternalsFromJsonDb = (): [string, DbInstanceEntry][] => {
  const db = getDb();
  const collection = db.get(`${DRE.network.name}.external`);
  const value = collection.value() as DbInstanceEntry[] | undefined;

  return Object.entries<DbInstanceEntry>(value || []);
};

export const getNamedFromJsonDb = (): [string, DbNamedEntry][] => {
  const db = getDb();
  const collection = db.get(`${DRE.network.name}.named`);
  const value = collection.value() as DbNamedEntry[] | undefined;

  return Object.entries<DbNamedEntry>(value || []);
};

export const getFromJsonDb = <T>(id: string): T => {
  const db = getDb();
  const collection = db.get(`${DRE.network.name}.named.${id}`);

  return collection.value() as T;
};

export const getAddrFromJsonDb = (id: string): string => getFromJsonDb<DbNamedEntry>(id)?.address;

export const hasInJsonDb = (id: string): boolean => notFalsyOrZeroAddress(getAddrFromJsonDb(id));

export const getInstanceCountFromJsonDb = (): number => getInstancesFromJsonDb().length;
export const getExternalCountFromJsonDb = (): number => getExternalsFromJsonDb().length;

export const printContracts = (deployer: string): [Map<string, EthereumAddress>, number, number] => {
  const currentNetwork = DRE.network.name;

  console.log('Contracts deployed at', currentNetwork, 'by', deployer);
  console.log('---------------------------------');

  const entries = getNamedFromJsonDb();
  const instEntries = getInstancesFromJsonDb() ?? [];
  const extrEntries = getExternalsFromJsonDb() ?? [];
  const total = instEntries.length + extrEntries.length;

  let multiCount = 0;
  const entryMap = new Map<string, EthereumAddress>();

  entries.forEach(([key, value]: [string, DbNamedEntry]) => {
    if (value.count > 1) {
      console.log(`\t${key}: N=${value.count}`);
      multiCount += 1;
    } else {
      console.log(`\t${key}: ${value.address}`);
      entryMap.set(key, value.address);
    }
  });

  console.log('---------------------------------');
  console.log('N# Contracts:', entryMap.size + multiCount, '/', total);

  return [entryMap, total, multiCount];
};

const getUiConfig = () => low(new FileSync('./ui-config.json'));

export const cleanupUiConfig = (): void => {
  const db = getUiConfig();
  db.setState(null).write();
};

export const writeUiConfig = (network: string, accessController: string, dataHelper: string): void => {
  const db = getUiConfig();
  db.setState({
    network,
    accessController,
    dataHelper,
  }).write();
};
