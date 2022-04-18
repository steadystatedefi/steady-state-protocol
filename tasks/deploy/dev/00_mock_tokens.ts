/* eslint-disable */
// TODO: enable later
import { subtask } from 'hardhat/config';

subtask('dev:deploy-mock-tokens', 'Deploy mock tokens for dev enviroment').setAction(async ({ verify }, localBRE) => {
  await localBRE.run('set-DRE');
  //    await deployAllMockTokens();
});
