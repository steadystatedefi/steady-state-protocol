import { Signer } from 'ethers';
import rawBRE from 'hardhat';

import _ from 'lodash';
import { loadTestConfig } from '../../helpers/config_loader';
import { getSigners } from '../../helpers/runtime-utils';
import { initializeMakeSuite } from './setup/make-suite';

const deployConfig = loadTestConfig();

const buildTestEnv = async (deployer: Signer, secondaryWallet: Signer) => {
  console.time('setup');

  // Do whole setup here

  console.timeEnd('setup');
};

before(async () => {
  await rawBRE.run('set-DRE');
  const [deployer, secondaryWallet] = await getSigners();

  if (process.env.MAINNET_FORK === 'true') {
    await rawBRE.run('deploy:full');
  } else {
    console.log('-> Deploying test environment...');
    await buildTestEnv(deployer, secondaryWallet);
  }

  await initializeMakeSuite();
  console.log('\n***************');
  console.log('Setup and snapshot finished');
  console.log('***************\n');
});
