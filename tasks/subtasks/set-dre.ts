import { subtask } from 'hardhat/config';

import { DRE, setDRE, DREWithPlugins } from '../../helpers/dre';

subtask(`set-DRE`, `Inits the DRE, to have access to all the plugins' objects`).setAction((_, dre) => {
  if (DRE) {
    return Promise.resolve();
  }

  setDRE(dre as DREWithPlugins);

  return Promise.resolve(dre);
});
