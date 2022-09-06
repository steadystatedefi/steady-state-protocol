import { task } from 'hardhat/config';

import { printContracts } from '../../helpers/deploy-db';
import { dreAction } from '../../helpers/dre';
import { getFirstSigner } from '../../helpers/runtime-utils';

task('print-contracts').setAction(
  dreAction(async () => {
    printContracts((await getFirstSigner()).address);
  })
);
