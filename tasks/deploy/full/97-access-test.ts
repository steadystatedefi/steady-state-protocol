import { task } from 'hardhat/config';

import { ConfigNamesAsString } from '../../../helpers/config-loader';
import { EAllNetworks } from '../../../helpers/config-networks';
import { getExternalsFromJsonDb, getInstancesFromJsonDb } from '../../../helpers/deploy-db';
import { getNetworkName, getNthSigner, getSigner } from '../../../helpers/runtime-utils';

task(`full:access-test`, 'Smoke test')
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
    const user = (await getNthSigner(1))!;

    console.log('Check access to mutable methods');

    const hasErorrs = false;
    for (const [addr, entry] of getInstancesFromJsonDb()) {
      const name = `${entry.id} ${addr}`;

      // const [contractId, getter] = getContractGetterById(entry.id);
      // if (getter == undefined) {
      //   hasErorrs = true;
      //   console.log(`\tError: unknown getter ${name}`);
      //   if (!checkAll) {
      //     throw `Unable to check contract - unknown getter ${name}`;
      //   }
      //   continue;
      // }
      // const subj = (await getter(addr)) as Contract;
      // console.log(`\tChecking: ${name}`);
      // await verifyContractMutableAccess(user, subj, contractId, estimateGas, checkAll);
    }

    for (const [addr, entry] of getExternalsFromJsonDb()) {
      const implAddr = entry.verify?.impl;
      if (!implAddr) {
        continue;
      }
      // const implId = getFromJsonDbByAddr(implAddr).id;
      // const name = `${entry.id} ${addr} => ${implId} ${implAddr}`;

      // const [contractId, getter] = getContractGetterById(implId);
      // if (getter == undefined) {
      //   console.log(`\tError: unknown getter ${name}`);
      //   if (!checkAll) {
      //     throw `Unable to check contract - unknown getter ${name}`;
      //   }
      //   continue;
      // }
      // const subj = (await getter(addr)) as Contract;
      // console.log(`\tChecking: ${name}`);
      // await verifyProxyMutableAccess(user, subj, contractId, estimateGas, checkAll);
    }

    if (hasErorrs) {
      throw new Error('Mutable access check has failed');
    }

    console.log('');
  });
