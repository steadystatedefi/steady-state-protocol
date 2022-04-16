import { BigNumber } from 'ethers';
import { task, types } from 'hardhat/config';

import { exit } from 'process';

import { ConfigNames } from '../../helpers/config-loader';
import { cleanupJsonDb, printContracts } from '../../helpers/deploy-db';
import { getFirstSigner } from '../../helpers/runtime-utils';
import { getDeploySteps } from '../deploy/deploy-steps';

interface IActionArgs {
  incremental: boolean;
  secure: boolean;
  strict: boolean;
  verify: boolean;
  skip: number;
}

task('deploy-full', 'Deploy full enviroment')
  .addFlag('incremental', 'Incremental deployment')
  .addFlag('secure', 'Renounce credentials on errors')
  .addFlag('strict', 'Fail on warnings')
  .addFlag('verify', 'Verify contracts at Etherscan')
  .addOptionalParam('skip', 'Skip steps with less or equal index', 0, types.int)
  .setAction(async ({ incremental, secure, strict, verify, skip: skipN }: IActionArgs, DRE) => {
    const CONFIG_NAME = ConfigNames.Full;
    await DRE.run('set-DRE');

    const deployer = await getFirstSigner();
    const startBalance: BigNumber = await deployer.getBalance();

    let renounce = false;
    let success = false;

    try {
      // cleanupUiConfig();
      console.log('Deployer start balance: ', startBalance.div(1e12).toNumber() / 1e6);

      if (incremental) {
        console.log('======================================================================');
        console.log('======================================================================');
        console.log('====================    ATTN! INCREMENTAL MODE    ====================');
        console.log('======================================================================');
        console.log(`=========== Delete 'deployed-contracts.json' to start anew ===========`);
        console.log('======================================================================');
        console.log('======================================================================');
      } else {
        cleanupJsonDb(DRE.network.name);
        renounce = secure;
      }

      console.log('Deployment started\n');
      const trackVerify = true;

      const steps = await getDeploySteps('full', {
        cfg: CONFIG_NAME,
        verify: trackVerify,
      });

      for (let index = 0; index < steps.length; index += 1) {
        const step = steps[index];
        const stepId = `0${step.seqId}`;
        console.log('\n======================================================================');
        console.log(stepId.substring(stepId.length - 2), step.stepName);
        console.log('======================================================================\n');
        if (step.seqId <= skipN) {
          console.log('STEP WAS SKIPPED\n');
        } else {
          await DRE.run(step.taskName, step.args);
        }
      }

      console.log('\n======================================================================');
      console.log('97 Access test');
      console.log('======================================================================\n');
      await DRE.run('full:access-test', { cfg: CONFIG_NAME });

      console.log('\n======================================================================');
      console.log('98 Smoke tests');
      console.log('======================================================================\n');
      await DRE.run('full:smoke-test', { cfg: CONFIG_NAME });

      {
        const signer = await getFirstSigner();
        const [entryMap, instanceCount, multiCount] = printContracts(signer.address);

        let hasWarn = false;
        if (multiCount > 0) {
          console.error('WARNING: multi-deployed contract(s) detected');
          hasWarn = true;
        } else if (entryMap.size !== instanceCount) {
          console.error('WARNING: unknown contract(s) detected');
          hasWarn = true;
        }

        entryMap.forEach((value, key) => {
          if (key.startsWith('Mock')) {
            console.error('WARNING: mock contract detected:', key);
            hasWarn = true;
          }
        });

        if (hasWarn && strict) {
          throw new Error('warnings are present');
        }
      }

      renounce = true;
      success = true;
    } catch (err) {
      console.error('\n=========================================================\nERROR:', err, '\n');
    }

    if (renounce || success) {
      try {
        console.log('\n======================================================================');
        console.log('99. Finalize');
        console.log('======================================================================\n');
        await DRE.run('full:deploy-finalize', { cfg: CONFIG_NAME, register: success });
      } catch (err) {
        console.log('Error during finalization & renouncement');
        console.error(err);
      }
    }

    {
      const endBalance = await deployer.getBalance();
      console.log('======================================================================');
      console.log('Deployer end balance: ', endBalance.div(1e12).toNumber() / 1e6);
      console.log('Deploy expenses: ', startBalance.sub(endBalance).div(1e12).toNumber() / 1e6);
      const { gasPrice } = DRE.network.config;
      if (gasPrice !== 'auto') {
        console.log(
          'Deploy gas     : ',
          startBalance.sub(endBalance).div(gasPrice).toNumber(),
          '@',
          gasPrice / 1e9,
          ' gwei'
        );
      }
      console.log('======================================================================');
    }

    if (!success) {
      console.log('\nDeployment has failed');
      exit(1);
    }

    // console.log('Write UI config');
    // await DRE.run('full:write-ui-config', { cfg: CONFIG_NAME });

    console.log('\nDeployment has finished');

    if (verify) {
      console.log('N. Verify all contracts');
      await DRE.run('verify-all-contracts', { cfg: CONFIG_NAME });
    }
  });
