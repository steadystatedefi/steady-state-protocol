import { task } from 'hardhat/config';

import { verifyContractMutableAccess, verifyProxyMutableAccess } from '../../../helpers/access-verify/method-checker';
import { ConfigNamesAsString } from '../../../helpers/config-loader';
import { EAllNetworks } from '../../../helpers/config-networks';
import { findFactory } from '../../../helpers/contract-types';
import { getExternalsFromJsonDb, getFromJsonDbByAddr, getInstancesFromJsonDb } from '../../../helpers/deploy-db';
import { getNetworkName, getNthSigner } from '../../../helpers/runtime-utils';

task(`full:access-test`, 'Check access to mutable methods of contracts')
  .addParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
  .setAction(async () => {
    // await localBRE.run('set-DRE');
    // const network = <eNetwork>localBRE.network.name;
    // const poolConfig = loadRuntimeConfig(pool);
    switch (getNetworkName()) {
      case EAllNetworks.kovan:
      case EAllNetworks.arbitrum_testnet:
        console.log('Access test is not supported for:', getNetworkName());
        return;
      default:
    }

    const estimateGas = true; // !isForkNetwork();

    const checkAll = true;
    const user = await getNthSigner(1);
    if (!user) {
      throw new Error('A separate user account is required');
    }

    console.log('Check access to mutable methods');

    let hasErorrs = false;

    const getTypedContract = (name: string, entry: { id: string; factory: string }, addr: string) => {
      const factory = findFactory(entry.factory);
      if (factory) {
        return factory.attach(addr);
      }
      const msg = `Unable to find factory: ${entry.factory} for ${name}`;
      hasErorrs = true;
      console.log('\t', msg);
      if (!checkAll) {
        throw new Error(msg);
      }
      return null;
    };

    for (const [addr, entry] of getInstancesFromJsonDb()) {
      const name = `${entry.id} ${addr}`;
      const subj = getTypedContract(name, entry, addr);
      if (!subj) {
        continue;
      }
      console.log(`\tChecking: ${name}`);
      await verifyContractMutableAccess(user, subj, entry.factory, estimateGas, checkAll);
    }

    for (const [addr, extEntry] of getExternalsFromJsonDb()) {
      const implAddr = extEntry.verify?.impl;
      if (!implAddr) {
        continue;
      }
      const entry = getFromJsonDbByAddr(implAddr);
      const name = `${extEntry.id} ${addr} => ${entry.id} ${implAddr}`;
      const subj = getTypedContract(name, entry, addr);
      if (!subj) {
        continue;
      }
      console.log(`\tChecking: ${name}`);
      await verifyProxyMutableAccess(user, subj, entry.factory, estimateGas, checkAll);
    }

    if (hasErorrs) {
      throw new Error('Mutable access check has failed');
    }

    console.log('');
  });
