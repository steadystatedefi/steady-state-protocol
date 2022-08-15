import { BigNumber } from 'ethers';
import { task } from 'hardhat/config';

import { exit } from 'process';

import { ConfigNames } from '../../helpers/config-loader';
import { cleanupJsonDb } from '../../helpers/deploy-db';
import { DRE, dreAction } from '../../helpers/dre';
import { getFirstSigner, getNetworkName } from '../../helpers/runtime-utils';
import { getDeploySteps } from '../deploy/deploy-steps';

task('deploy-dev', 'Deploy dev enviroment').setAction(
  dreAction(async () => {
    const CONFIG_NAME = ConfigNames.Test;

    const deployer = await getFirstSigner();
    const startBalance: BigNumber = await deployer.getBalance();

    const renounce = false;
    let success = false;

    try {
      console.log('Deployer start balance: ', startBalance.div(1e12).toNumber() / 1e6);

      cleanupJsonDb(getNetworkName());

      console.log('Deployment started\n');

      const stepCfg = {
        cfg: CONFIG_NAME,
        verify: false,
      };
      const devSteps = await getDeploySteps('dev', stepCfg);
      const fullSteps = await getDeploySteps('full', stepCfg);

      {
        const step = devSteps[0];
        console.log('\n======================================================================');
        console.log('00', step.stepName);
        console.log('======================================================================\n');
        await DRE.run(step.taskName, step.args);
      }

      for (const step of fullSteps) {
        const stepId = `0${step.seqId}`;
        console.log('\n======================================================================');
        console.log(stepId.substring(stepId.length - 2), step.stepName);
        console.log('======================================================================\n');
        await DRE.run(step.taskName, step.args);
      }

      const seqBase = fullSteps[fullSteps.length - 1].seqId - 1;

      for (const step of devSteps.slice(1)) {
        const stepId = `0${step.seqId + seqBase}`;
        console.log('\n======================================================================');
        console.log(stepId.substring(stepId.length - 2), step.stepName);
        console.log('======================================================================\n');
        await DRE.run(step.taskName, step.args);
      }

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
      const gasPrice = DRE.network.config.gasPrice;
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

    console.log('\nDeployment has finished');
  })
);
