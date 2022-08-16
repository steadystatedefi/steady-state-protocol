import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { TracerDependenciesExtended } from 'hardhat-tracer/dist/src/types';
import { ActionType, HardhatRuntimeEnvironment, RunSuperFunction, TaskArguments } from 'hardhat/types';

import { setDefaultDeployer } from './factory-wrapper';
import { getFirstSigner } from './runtime-utils';

interface EtherscanExtender {
  config: {
    etherscan: { apiKey?: string };
  };
}

interface EthersExtender {
  ethers: HardhatEthersHelpers;
}

interface TracerExtender {
  tracer: TracerDependenciesExtended;
}

export type DREWithPlugins = HardhatRuntimeEnvironment & EthersExtender & TracerExtender & EtherscanExtender;

// eslint-disable-next-line import/no-mutable-exports
export let DRE: DREWithPlugins;

export const setDRE = (dre: DREWithPlugins): void => {
  DRE = dre;
  Object.freeze(DRE);
};

export const chainId = (): number => DRE.network.config.chainId ?? -1;

export function dreAction<ArgsT extends TaskArguments>(action: ActionType<ArgsT>): ActionType<ArgsT> {
  return (taskArgs: ArgsT, env: HardhatRuntimeEnvironment, runSuper: RunSuperFunction<ArgsT>): Promise<unknown> => {
    setDRE(env as DREWithPlugins);
    return getFirstSigner().then((deployer) => {
      setDefaultDeployer(deployer);
      return action(taskArgs, env, runSuper);
    });
  };
}
