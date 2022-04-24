import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

task('storage-layout', 'Print storage layout of contracts')
  .setAction(async (_, DRE: HardhatRuntimeEnvironment) => {
    await DRE.run('set-DRE');

    await DRE.storageLayout.export();
  });
