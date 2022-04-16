import { subtask } from 'hardhat/config';

subtask('dev:deploy-mock-tokens', 'Deploy mock tokens for dev enviroment').setAction(async (_, localBRE) => {
  await localBRE.run('set-DRE');
  //    await deployAllMockTokens();
});
