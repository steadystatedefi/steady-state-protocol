import { task, types } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { verifyContractStringified, verifyProxy } from '../../helpers/contract-verification';
import {
  DbInstanceEntry,
  getExternalsFromJsonDb,
  getInstancesFromJsonDb,
  getVerifiedFromJsonDb,
  setVerifiedToJsonDb,
} from '../../helpers/deploy-db';
import { falsyOrZeroAddress } from '../../helpers/runtime-utils';

interface IActionArgs {
  n: number;
  of: number;
  filter: string[];
  proxy: string;
  force: boolean;
}

task('verify-all-contracts', 'Verify contracts listed in DeployDB')
  .addFlag('force', 'Ignore verified status')
  .addOptionalParam('n', 'Batch index, 0 <= n < total number of batches', 0, types.int)
  .addOptionalParam('of', 'Total number of batches, > 0', 1, types.int)
  .addOptionalParam('proxy', 'Proxy verification mode: auto, full, min', 'auto', types.string)
  .addOptionalVariadicPositionalParam('filter', 'Names or addresses of contracts to verify', [], types.string)
  .setAction(async ({ n, of, filter, proxy, force }: IActionArgs, DRE: HardhatRuntimeEnvironment) => {
    await DRE.run('set-DRE');

    if (n >= of) {
      throw new Error('invalid batch parameters');
    }

    let filterProxy: () => boolean;
    switch (proxy.toLowerCase()) {
      case 'auto': {
        let hasFirst = false;

        filterProxy = () => {
          if (hasFirst) {
            return false;
          }
          hasFirst = true;
          return true;
        };
        break;
      }
      case 'full':
        filterProxy = () => true;
        break;
      case 'min':
      default:
        filterProxy = () => false;
        break;
    }

    const filterSet = new Map<string, string>();
    filter.forEach((value) => {
      filterSet.set(value.toUpperCase(), value);
    });
    const hasFilter = filterSet.size > 0;

    const addrList: string[] = [];
    const entryList: DbInstanceEntry[] = [];
    let batchIndex = 0;

    const addEntry = (address: string, entry: DbInstanceEntry) => {
      if (!entry.verify) {
        return;
      }

      if (hasFilter) {
        let found = false;
        const values = [address, entry.id];

        for (let index = 0; index < values.length; index += 1) {
          const key = values[index];
          const kv = key.toUpperCase();

          if (filterSet.has(kv)) {
            found = true;
            if (key === address) {
              filterSet.delete(kv);
            }
            break;
          }
        }

        if (!found) {
          return;
        }
      }

      batchIndex += 1;
      if ((batchIndex - 1) % of !== n) {
        return;
      }
      addrList.push(address);
      entryList.push(entry);
    };

    const instances = getInstancesFromJsonDb();
    for (let index = 0; index < instances.length; index += 1) {
      const [key, entry] = instances[index];
      addEntry(key, entry);
    }

    const externals = getExternalsFromJsonDb();
    for (let index = 0; index < externals.length; index += 1) {
      const [key, entry] = externals[index];
      addEntry(key, entry);
    }

    filterSet.forEach((value, key) => {
      if (falsyOrZeroAddress(value)) {
        return;
      }

      addEntry(value, {
        id: `ID_${key}`,
        verify: {
          args: '[]',
        },
      });
    });

    console.log('======================================================================');
    console.log('======================================================================');
    console.log(`Verification batch ${n} of ${of} with ${addrList.length} entries of ${batchIndex} total.`);
    console.log('======================================================================');

    const summary: string[] = [];
    for (let i = 0; i < addrList.length; i += 1) {
      const addr = addrList[i];
      const entry = entryList[i];

      const params = entry.verify;

      console.log('\n======================================================================');
      console.log(`[${i}/${addrList.length}] Verify contract: ${entry.id} ${addr}`);
      console.log('\tArgs:', params?.args);

      let fullVerify = true;
      if (params?.impl) {
        console.log('\tProxy impl: ', params.impl);
        fullVerify = filterProxy();
      }

      if (!force && (await getVerifiedFromJsonDb(addr))) {
        console.log('Already verified');
        // eslint-disable-next-line no-continue
        continue;
      }

      let [ok, err] = fullVerify ? await verifyContractStringified(addr, params?.args ?? '') : [true, ''];
      if (err) {
        console.log(err);
      }
      if (ok && params?.impl) {
        [ok, err] = await verifyProxy(addr, params.impl);
        if (err) {
          console.log(err);
        }
      }
      if (ok) {
        setVerifiedToJsonDb(addr, true);
      } else {
        summary.push(`${addr} ${entry.id}: ${err}`);
      }
    }

    console.log(`\n`);
    console.log('======================================================================');
    console.log(`Verification batch ${n} of ${of} has finished with ${summary.length} issue(s).`);
    console.log('======================================================================');
    console.log(summary.join('\n'));
    console.log('======================================================================');
  });
