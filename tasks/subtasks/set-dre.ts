/* eslint-disable */
// TODO: enable later
import { subtask } from 'hardhat/config';
import { DRE, setDRE, DREWithPlugins } from '../../helpers/dre';

subtask(`set-DRE`, `Inits the DRE, to have access to all the plugins' objects`).setAction(async (_, _DRE) => {
  if (DRE) {
    return;
  }

  setDRE(_DRE as DREWithPlugins);
  return _DRE;
});
