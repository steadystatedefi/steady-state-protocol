import { loadRuntimeConfig } from '../../../helpers/config-loader';
import { eNetwork } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

const CONTRACT_NAME = 'Sample';

deployTask(`full:example`, 'Deploy ' + CONTRACT_NAME, __dirname).setAction(async ({ cfg, verify }, localBRE) => {
  await localBRE.run('set-DRE');
  const network = <eNetwork>localBRE.network.name;
  const poolConfig = loadRuntimeConfig(cfg);

  //    console.log(`${CONTRACT_NAME}:`, contract.address);
});
