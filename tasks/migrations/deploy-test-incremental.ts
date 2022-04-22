/* eslint-disable */
// TODO: enable later
import { task } from 'hardhat/config';
import { exit } from 'process';
import { ConfigNames } from '../../helpers/config-loader';
import { setDefaultDeployer } from '../../helpers/factory-wrapper';
import { cleanupJsonDb, getInstanceCountFromJsonDb, printContracts } from '../../helpers/deploy-db';
import { getFirstSigner, isForkNetwork } from '../../helpers/runtime-utils';
import { tEthereumAddress } from '../../helpers/types';
import { getDeploySteps } from '../deploy/deploy-steps';

task('deploy:test-incremental', 'Test incremental deploy').setAction(async ({}, DRE) => {
  const CONFIG_NAME = ConfigNames.Full;
  await DRE.run('set-DRE');
  cleanupJsonDb(DRE.network.name);
  // cleanupUiConfig();

  const deployer = await getFirstSigner();
  setDefaultDeployer(deployer);

  if (!isForkNetwork()) {
    console.log('Can only run on fork');
    exit(1);
  }

  try {
    let lastEntryMap = new Map<string, tEthereumAddress>();
    let lastInstanceCount = 0;
    let stop = false;
    const trackVerify = false;

    const steps = await getDeploySteps('full', {
      cfg: CONFIG_NAME,
      verify: trackVerify,
    });

    for (let maxStep = 1; ; maxStep++) {
      if (maxStep > 1) {
        const [entryMap, instanceCount, multiCount] = printContracts((await getFirstSigner()).address);
        if (multiCount > 0) {
          throw `illegal multi-deployment detected after step ${maxStep}`;
        }
        if (lastInstanceCount > instanceCount || lastEntryMap.size > entryMap.size) {
          throw `impossible / jsonDb is broken after step ${maxStep}`;
        }
        if (!checkUnchanged(lastEntryMap, entryMap)) {
          throw `some contracts were redeployed after step ${maxStep}`;
        }
        entryMap.forEach((value, key, m) => {
          if (key.startsWith('Mock')) {
            throw 'mock contract(s) detected';
          }
        });

        lastInstanceCount = instanceCount;
        lastEntryMap = entryMap;
      }
      if (stop) {
        break;
      }

      console.log('======================================================================');
      console.log('======================================================================');
      console.log(`Incremental deploy cycle #${maxStep} started\n`);
      let step = maxStep;

      const isLastStep = () => {
        if (step == 2) {
          if (lastInstanceCount != getInstanceCountFromJsonDb()) {
            throw `unexpected contracts were deployed at step #${1 + maxStep - step}`;
          }
        }
        return --step == 0;
      };

      stop = true;
      for (const step of steps) {
        const stepId = '0' + step.seqId;
        console.log('\n======================================================================');
        console.log(stepId.substring(stepId.length - 2), step.stepName);
        console.log('======================================================================\n');
        await DRE.run(step.taskName, step.args);
        if (isLastStep()) {
          stop = false;
          break;
        }
      }
    }

    console.log('Smoke test');
    await DRE.run('full:smoke-test', { cfg: CONFIG_NAME });
  } catch (err) {
    console.error(err);
    exit(1);
  }

  cleanupJsonDb(DRE.network.name);
});

const checkUnchanged = <T1, T2>(prev: Map<T1, T2>, next: Map<T1, T2>) => {
  let unchanged = true;
  prev.forEach((value, key, m) => {
    const nextValue = next.get(key);
    if (nextValue != value) {
      console.log(`${key} was changed: ${value} => ${nextValue}`);
      unchanged = false;
    }
  });
  return unchanged;
};
