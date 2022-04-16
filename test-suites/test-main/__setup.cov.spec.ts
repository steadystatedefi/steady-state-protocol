import { Signer } from 'ethers';
import rawBRE from 'hardhat';

import { setDefaultDeployer } from '../../helpers/factory-wrapper';
import { getSigners, isForkNetwork } from '../../helpers/runtime-utils';

import { initializeMakeSuite } from './setup/make-suite';

// const deployConfig = loadTestConfig();

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const buildTestEnv = (_deployer: Signer, _secondaryWallet: Signer) => {
  console.time('setup');

  // Do whole setup here
  // const po = await Factories.PriceOracle.deploy(USD_ADDRESS, ZERO_ADDRESS, [], []);
  // const po2 = Factories.PriceOracle.get();

  console.timeEnd('setup');
};

before(async () => {
  await rawBRE.run('set-DRE');
  const [deployer, secondaryWallets] = await getSigners();
  setDefaultDeployer(deployer);

  if (isForkNetwork()) {
    await rawBRE.run('deploy:full');
  } else {
    console.log('-> Deploying test environment...');
    buildTestEnv(deployer, secondaryWallets);
  }

  await initializeMakeSuite(rawBRE.network.name === 'coverage');
  console.log('\n***************');
  console.log('Setup and snapshot finished');
  console.log('***************\n');
});
