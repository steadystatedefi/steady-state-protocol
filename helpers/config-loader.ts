import { IConfiguration, INetworkConfiguration } from './config-types';
import { DevConfig } from './config/dev';
import { FullConfig } from './config/full';
import { getNetworkName } from './runtime-utils';

export enum ConfigNames {
  Full = 'Full',
  Test = 'Test',
}

const configs: Record<keyof typeof ConfigNames, IConfiguration> = {
  Test: DevConfig,
  Full: FullConfig,
};

export const ConfigNamesAsString = JSON.stringify([...Object.keys(configs)]);

export const loadRuntimeConfig = (configName: string): IConfiguration => {
  const cfg = configs[configName] as IConfiguration;
  if (!cfg) {
    throw new Error(`Unknown configuration: ${String(configName)} ${ConfigNamesAsString}`);
  }
  return cfg;
};

export const loadTestConfig = (): IConfiguration => loadRuntimeConfig(ConfigNames.Test);

export const getNetworkConfig = (cfg: IConfiguration, network?: string): INetworkConfiguration => {
  const name = network || getNetworkName();
  const nc = cfg?.[name];
  if (!nc) {
    throw new Error(`Unknown network configuration: ${String(name)} ${JSON.stringify([...Object.keys(cfg)])}`);
  }
  return nc;
};

export const loadNetworkConfig = (configName: string, network?: string): INetworkConfiguration =>
  getNetworkConfig(loadRuntimeConfig(configName), network);
