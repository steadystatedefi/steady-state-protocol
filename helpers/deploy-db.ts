import low from 'lowdb';
import FileSync from 'lowdb/adapters/FileSync';
import { Contract } from 'ethers';
import { eEthereumNetwork, tEthereumAddress } from './types';
import { stringifyArgs } from './etherscan-verification';
import { DRE } from './dre';
import { notFalsyOrZeroAddress } from './runtime-utils';
import { MAINNET_FORK } from './env-utils';

const getDb = () => low(new FileSync('./deployed-contracts.json'));

export interface DbNamedEntry {
  address: string;
  count: number;
}

export interface DbInstanceEntry {
  id: string;
  verify?: {
    args?: string;
    impl?: string;
    subType?: string;
  };
}

export const cleanupJsonDb = (currentNetwork: string) => {
  getDb().set(`${currentNetwork}`, {}).write();
};

export const addContractToJsonDb = (
  contractId: string,
  contractInstance: Contract,
  register: boolean,
  verifyArgs?: any[]
) => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  if (MAINNET_FORK || (currentNetwork !== eEthereumNetwork.hardhat && !currentNetwork.includes('coverage'))) {
    console.log(`*** ${contractId} ***\n`);
    console.log(`Network: ${currentNetwork}`);
    console.log(`tx: ${contractInstance.deployTransaction.hash}`);
    console.log(`contract address: ${contractInstance.address}`);
    console.log(`deployer address: ${contractInstance.deployTransaction.from}`);
    console.log(`gas price: ${contractInstance.deployTransaction.gasPrice}`);
    console.log(`gas used: ${contractInstance.deployTransaction.gasLimit}`);
    console.log(`\n******`);
    console.log();
  }

  let logEntry: DbInstanceEntry = {
    id: contractId,
  };

  if (verifyArgs != undefined) {
    logEntry.verify = {
      args: stringifyArgs(verifyArgs!),
    };
  }

  db.set(`${currentNetwork}.instance.${contractInstance.address}`, logEntry).write();

  if (register) {
    const node = `${currentNetwork}.named.${contractId}`;
    const count = (db.get(node).value())?.count || 0;
    let namedEntry: DbNamedEntry = {
      address: contractInstance.address,
      count: count + 1,
    };
    db.set(`${currentNetwork}.named.${contractId}`, namedEntry).write();
  }
};

export const addProxyToJsonDb = (
  id: string,
  proxyAddress: string,
  implAddress: string,
  subType: string,
  verifyArgs?: any[]
) => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  let logEntry: DbInstanceEntry = {
    id: id,
    verify: {
      impl: implAddress,
      subType: subType,
    },
  };

  if (verifyArgs != undefined) {
    logEntry.verify!.args = stringifyArgs(verifyArgs!);
  }

  db.set(`${currentNetwork}.external.${proxyAddress}`, logEntry).write();
};

export const addExternalToJsonDb = (id: string, address: string, verifyArgs?: any[]) => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  let logEntry: DbInstanceEntry = {
    id: id,
    verify: {},
  };

  if (verifyArgs != undefined) {
    logEntry.verify!.args = stringifyArgs(verifyArgs!);
  }

  db.set(`${currentNetwork}.external.${address}`, logEntry).write();
};

export const addNamedToJsonDb = (contractId: string, contractAddress: string) => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  const node = `${currentNetwork}.named.${contractId}`;
  const nodeValue = db.get(node).value();

  db.set(`${currentNetwork}.named.${contractId}`, {
      address: contractAddress,
      count: 1 + (nodeValue?.count || 0),
    })
    .write();
};

export const setVerifiedToJsonDb = (address: string, verified: boolean) => {
  const currentNetwork = DRE.network.name;
  const db = getDb();
  db.set(`${currentNetwork}.verified.${address}`, verified).write();
};

export const getVerifiedFromJsonDb = (address: string) => {
  const currentNetwork = DRE.network.name;
  const db = getDb();
  return (db.get(`${currentNetwork}.verified.${address}`).value()) as boolean;
};

export const getInstanceFromJsonDb = (addr: tEthereumAddress) =>
  <DbInstanceEntry>getDb().get(`${DRE.network.name}.instance.${addr}`).value();

export const getInstancesFromJsonDb = () =>
  Object.entries<DbInstanceEntry>(getDb().get(`${DRE.network.name}.instance`).value() || []);

export const getExternalsFromJsonDb = () =>
  Object.entries<DbInstanceEntry>(getDb().get(`${DRE.network.name}.external`).value() || []);

export const getNamedFromJsonDb = () =>
  Object.entries<DbNamedEntry>(getDb().get(`${DRE.network.name}.named`).value() || []);

export const getFromJsonDb = (id: string): DbNamedEntry => getDb().get(`${DRE.network.name}.named.${id}`).value();

export const getFromJsonDbByAddr = (id: string) =>
  getDb().get(`${DRE.network.name}.instance.${id}`).value() as DbInstanceEntry;

export const hasInJsonDb = (id: string) => notFalsyOrZeroAddress(getFromJsonDb(id)?.address);

export const getInstanceCountFromJsonDb = () => {
  return getInstancesFromJsonDb().length;
};

export const printContracts = (deployer: string): [Map<string, tEthereumAddress>, number, number] => {
  const currentNetwork = DRE.network.name;
  const db = getDb();

  console.log('Contracts deployed at', currentNetwork, 'by', deployer);
  console.log('---------------------------------');

  const entries = getNamedFromJsonDb();
  const logEntries = getInstancesFromJsonDb();

  let multiCount = 0;
  const entryMap = new Map<string, tEthereumAddress>();
  entries.forEach(([key, value]: [string, DbNamedEntry]) => {
    if (key.startsWith('~')) {
      return;
    } else if (value.count > 1) {
      console.log(`\t${key}: N=${value.count}`);
      multiCount++;
    } else {
      console.log(`\t${key}: ${value.address}`);
      entryMap.set(key, value.address);
    }
  });

  console.log('---------------------------------');
  console.log('N# Contracts:', entryMap.size + multiCount, '/', logEntries.length);

  return [entryMap, logEntries.length, multiCount];
};
