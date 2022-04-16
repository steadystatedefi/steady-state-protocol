import { deployTask } from '../deploy-steps';

const CONTRACT_NAME = 'Sample';

deployTask(`full:example`, `Deploy ${CONTRACT_NAME}`, __dirname).setAction(async (_, localBRE) => {
  await localBRE.run('set-DRE');
  // const network = <eNetwork>localBRE.network.name;
  // const poolConfig = loadRuntimeConfig(cfg);

  //    console.log(`${CONTRACT_NAME}:`, contract.address);
});
