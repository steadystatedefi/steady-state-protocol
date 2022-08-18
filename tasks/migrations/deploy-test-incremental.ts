import { task } from 'hardhat/config';

import { exit } from 'process';

import { ConfigNames } from '../../helpers/config-loader';
import { cleanupJsonDb, getInstanceCountFromJsonDb, printContracts } from '../../helpers/deploy-db';
import { setDefaultDeployer } from '../../helpers/factory-wrapper';
import { getFirstSigner, isForkNetwork } from '../../helpers/runtime-utils';
import { EthereumAddress } from '../../helpers/types';
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
    let lastEntryMap = new Map<string, EthereumAddress>();
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
          throw new Error(`illegal multi-deployment detected after step ${maxStep}`);
        }

        if (lastInstanceCount > instanceCount || lastEntryMap.size > entryMap.size) {
          throw new Error(`impossible / jsonDb is broken after step ${maxStep}`);
        }

        if (!checkUnchanged(lastEntryMap, entryMap)) {
          throw new Error(`some contracts were redeployed after step ${maxStep}`);
        }

        entryMap.forEach((_value, key) => {
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
      for (const deployStep of steps) {
        const stepId = `0${deployStep.seqId}`;
        console.log('\n======================================================================');
        console.log(stepId.substring(stepId.length - 2), deployStep.stepName);
        console.log('======================================================================\n');
        await DRE.run(deployStep.taskName, deployStep.args);

        if (step === 2) {
          if (lastInstanceCount !== getInstanceCountFromJsonDb()) {
            throw new Error(`unexpected contracts were deployed at step #${1 + maxStep - step}`);
          }
        }

        // eslint-disable-next-line no-plusplus
        if (--step === 0) {
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

function checkUnchanged<T1, T2>(prev: Map<T1, T2>, next: Map<T1, T2>) {
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
