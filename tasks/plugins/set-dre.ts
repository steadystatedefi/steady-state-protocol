import { subtask } from 'hardhat/config';

import { DRE, setDRE, DREWithPlugins } from '../../helpers/dre';

subtask(`set-DRE`, `Inits the DRE, to have access to all the plugins' objects`).setAction(async (_, dre) => {
  if (DRE) {
    return Promise.resolve(undefined);
  }

  setDRE(dre as DREWithPlugins);

  return Promise.resolve(dre);
});
