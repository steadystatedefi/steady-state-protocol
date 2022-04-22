import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { TracerDependenciesExtended } from 'hardhat-tracer/dist/src/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

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
