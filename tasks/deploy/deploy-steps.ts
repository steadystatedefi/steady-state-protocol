import { task } from 'hardhat/config';
import { ConfigurableTaskDefinition, TaskArguments } from 'hardhat/types';

import path from 'path';

import { ConfigNamesAsString } from '../../helpers/config-loader';

export interface IDeployStepParams {
  cfg: string;
  verify: boolean;
}

export interface IDeployStep {
  seqId: number;
  stepName: string;
  taskName: string;
  args: TaskArguments;
}

const stepCatalog = new Map<
  string,
  {
    stepName: string;
    taskName: string;
    paramsFn: (params: IDeployStepParams) => Promise<TaskArguments>;
  }[]
>();

stepCatalog.set('full', []);
stepCatalog.set('dev', []);

const defaultParams = (params: IDeployStepParams) => Promise.resolve({ cfg: params.cfg, verify: params.verify });

export function deployTask(
  name: string,
  description: string,
  moduleDir: string,
  paramsFn?: (params: IDeployStepParams) => Promise<TaskArguments>
): ConfigurableTaskDefinition {
  const deployType = name.substring(0, name.indexOf(':'));
  if (path.basename(moduleDir) !== deployType) {
    throw new Error(`Invalid location: ${deployType}, ${moduleDir}`);
  }

  addStep(deployType, description, name, paramsFn);
  return task(name, description)
    .addParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
    .addFlag('verify', `Verify contracts via Etherscan API.`);
}

function addStep(
  deployType: string,
  stepName: string,
  taskName: string,
  paramsFn?: (params: IDeployStepParams) => Promise<TaskArguments>
) {
  const steps = stepCatalog.get(deployType);
  if (steps === undefined) {
    throw new Error(`Unknown deploy type: ${deployType}`);
    // steps = [];
    // stepCatalog.set(deployType, steps);
  }

  // console.log('Deploy step registered:', deployType, steps.length + 1, stepName, '=>', taskName);
  steps.push({ stepName, taskName, paramsFn: paramsFn || defaultParams });
}

export const getDeploySteps = async (deployType: string, params: IDeployStepParams): Promise<IDeployStep[]> => {
  const stepList = stepCatalog.get(deployType);

  if (stepList === undefined) {
    throw new Error(`Unknown deploy type: ${deployType}`);
  }

  const steps: IDeployStep[] = [];

  for (let i = 0; i < stepList.length; i++) {
    const { stepName, taskName, paramsFn } = stepList[i];
    const args = (await paramsFn(params)) as Promise<TaskArguments>;

    steps.push({
      seqId: i + 1,
      stepName,
      taskName,
      args,
    });
  }

  return steps;
};
