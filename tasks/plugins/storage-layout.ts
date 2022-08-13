import { extendConfig, task } from 'hardhat/config';
import { HardhatConfig, HardhatRuntimeEnvironment } from 'hardhat/types';

import { extractContractLayout, tabulateContractLayouts } from '../../helpers/storage-layout';

// A much faster version of hardhat-storage-layout. Supports filtering.

task('storage-layout', 'Print storage layout of contracts')
  .addOptionalVariadicPositionalParam('contracts', 'Names of contracts')
  .setAction(async ({ contracts }, DRE: HardhatRuntimeEnvironment) => {
    try {
      const layouts = await extractContractLayout(DRE, contracts as string[]);
      if (!layouts?.length) {
        console.error('No contracts found');
      } else {
        const table = tabulateContractLayouts(layouts);
        table.printTable();
      }
    } catch (e) {
      console.log(e); // TODO HRE error handler
    }
  });

/* eslint-disable @typescript-eslint/no-unsafe-member-access,@typescript-eslint/no-unsafe-call,@typescript-eslint/no-unsafe-assignment */

extendConfig((config: HardhatConfig) => {
  for (const compiler of config.solidity.compilers) {
    compiler.settings ??= {};
    compiler.settings.outputSelection ??= {};
    compiler.settings.outputSelection['*'] ??= {};
    compiler.settings.outputSelection['*']['*'] ??= [];

    const outputs = compiler.settings.outputSelection['*']['*'];
    if (!outputs.includes('storageLayout')) {
      outputs.push('storageLayout');
    }
  }
});
