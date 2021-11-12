import { Signer } from 'ethers';
import rawBRE from 'hardhat';

import _ from 'lodash';
import { loadTestConfig } from '../../helpers/config_loader';
import { USD_ADDRESS, ZERO_ADDRESS } from '../../helpers/constants';
import { Factories, setDefaultDeployer } from '../../helpers/contract-types';
import { MAINNET_FORK } from '../../helpers/env-utils';
import { getSigners } from '../../helpers/runtime-utils';
import { initializeMakeSuite } from './setup/make-suite';

const deployConfig = loadTestConfig();

const buildTestEnv = async (deployer: Signer, secondaryWallet: Signer) => {
  console.time('setup');

  // Do whole setup here
  const po = await Factories.PriceOracle.deploy(USD_ADDRESS, ZERO_ADDRESS, [], []);
  // const po2 = Factories.PriceOracle.get();

  console.timeEnd('setup');
};

before(async () => {
  await rawBRE.run('set-DRE');
  const [deployer, secondaryWallet] = await getSigners();
  setDefaultDeployer(deployer);

  if (MAINNET_FORK) {
    await rawBRE.run('deploy:full');
  } else {
    console.log('-> Deploying test environment...');
    await buildTestEnv(deployer, secondaryWallet);
  }

  await initializeMakeSuite(rawBRE.network.name == 'coverage');
  console.log('\n***************');
  console.log('Setup and snapshot finished');
  console.log('***************\n');
});
