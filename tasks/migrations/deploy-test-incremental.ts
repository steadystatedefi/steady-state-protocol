import { task } from 'hardhat/config';

import { exit } from 'process';

import { ConfigNames } from '../../helpers/config-loader';
import { cleanupJsonDb, getInstanceCountFromJsonDb, printContracts } from '../../helpers/deploy-db';
import { setDefaultDeployer } from '../../helpers/factory-wrapper';
import { getFirstSigner, isForkNetwork } from '../../helpers/runtime-utils';
import { TEthereumAddress } from '../../helpers/types';
import { getDeploySteps } from '../deploy/deploy-steps';

task('deploy:test-incremental', 'Test incremental deploy').setAction(async (_, DRE) => {
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
    let lastEntryMap = new Map<string, TEthereumAddress>();
    let lastInstanceCount = 0;
    let stop = false;
    const trackVerify = false;

    const steps = await getDeploySteps('full', {
      cfg: CONFIG_NAME,
      verify: trackVerify,
    });

    for (let maxStep = 1; ; maxStep += 1) {
      if (maxStep > 1) {
        const [entryMap, instanceCount, multiCount] = printContracts((await getFirstSigner()).address);

        if (multiCount > 0) {
          throw new Error(`illegal multi-deployment detected after step ${maxStep}`);
        }

        if (lastInstanceCount > instanceCount || lastEntryMap.size > entryMap.size) {
          throw new Error(`impossible / jsonDb is broken after step ${maxStep}`);
        }

        if (!checkUnchanged(lastEntryMap, entryMap)) {
          throw new Error(`some contracts were redeployed after step ${maxStep}`);
        }

        entryMap.forEach((value, key) => {
          if (key.startsWith('Mock')) {
            throw new Error('mock contract(s) detected');
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

      stop = true;
      for (let index = 0; index < steps.length; index += 1) {
        const s = steps[index];
        const stepId = `0${s.seqId}`;
        console.log('\n======================================================================');
        console.log(stepId.substring(stepId.length - 2), s.stepName);
        console.log('======================================================================\n');
        await DRE.run(s.taskName, s.args);

        if (isLastStep({ lastInstanceCount, step, maxStep })) {
          stop = false;
          break;
        }

        step -= 1;
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

interface ILastStepArgs {
  lastInstanceCount: number;
  step: number;
  maxStep: number;
}

function isLastStep({ lastInstanceCount, step, maxStep }: ILastStepArgs): boolean {
  if (step === 2) {
    if (lastInstanceCount !== getInstanceCountFromJsonDb()) {
      throw new Error(`unexpected contracts were deployed at step #${1 + maxStep - step}`);
    }
  }

  return step - 1 === 0;
}

function checkUnchanged<T1, T2>(prev: Map<T1, T2>, next: Map<T1, T2>): boolean {
  let unchanged = true;

  prev.forEach((value, key) => {
    const nextValue = next.get(key);
    if (nextValue !== value) {
      console.log(`${String(key)} was changed: ${String(value)} => ${String(nextValue)}`);
      unchanged = false;
    }
  });

  return unchanged;
}
