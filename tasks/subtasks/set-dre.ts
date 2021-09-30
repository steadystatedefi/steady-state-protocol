import { subtask } from 'hardhat/config';
import { DRE, setDRE } from '../../helpers/dre';

subtask(`set-DRE`, `Inits the DRE, to have access to all the plugins' objects`).setAction(async (_, _DRE) => {
  if (DRE) {
    return;
  }
  setDRE(_DRE);
  return _DRE;
});
