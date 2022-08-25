import { task } from 'hardhat/config';

import { verifyContractMutableAccess, verifyProxyMutableAccess } from '../../../helpers/access-verify/method-checker';
import { ConfigNamesAsString } from '../../../helpers/config-loader';
import { EAllNetworks } from '../../../helpers/config-networks';
import { Factories } from '../../../helpers/contract-types';
import { getExternalsFromJsonDb, getInstanceFromJsonDb, getInstancesFromJsonDb } from '../../../helpers/deploy-db';
import { dreAction } from '../../../helpers/dre';
import { NamedAttachable } from '../../../helpers/factory-wrapper';
import { getNetworkName, getNthSigner } from '../../../helpers/runtime-utils';

task(`full:access-test`, 'Check access to mutable methods of contracts')
  .addOptionalParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
  .addFlag('failfast', `Stop on first error`)
  .setAction(
    dreAction(async (failfast) => {
      const checkAll = !failfast;
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

      const estimateGas = false; // !isForkNetwork();

      const user = await getNthSigner(1);
      if (!user) {
        throw new Error('A separate user account is required');
      }

      console.log('Check access to mutable methods');

      let hasErorrs = false;
      for (const [addr, entry] of getInstancesFromJsonDb()) {
        const name = `${entry.id} ${addr}`;

        const factory = Factories[entry.factory] as NamedAttachable;
        if (!factory) {
          const msg = `Unable to find factory: ${entry.factory} for ${name}`;
          hasErorrs = true;
          console.log('\t', msg);
          if (!checkAll) {
            throw new Error(msg);
          }
          continue;
        }

        const subj = factory.attach(addr);
        console.log(`\tChecking: ${name}`);
        await verifyContractMutableAccess(user, subj, entry.factory, estimateGas, checkAll);
      }

      for (const [addr, extEntry] of getExternalsFromJsonDb()) {
        const implAddr = extEntry.verify?.impl;
        if (!implAddr) {
          continue;
        }
        const entry = getInstanceFromJsonDb(implAddr);
        const name = `${extEntry.id} ${addr} => ${entry.id} ${implAddr}`;

        const factory = Factories[entry.factory] as NamedAttachable;
        if (!factory) {
          const msg = `Unable to find factory: ${entry.factory} for ${name}`;
          hasErorrs = true;
          console.log('\t', msg);
          if (!checkAll) {
            throw new Error(msg);
          }
          continue;
        }
        const subj = factory.attach(addr);
        console.log(`\tChecking: ${name}`);
        await verifyProxyMutableAccess(user, subj, entry.factory, estimateGas, checkAll);
      }

      if (hasErorrs) {
        throw new Error('Mutable access check has failed');
      }

      console.log('');
    })
  );
