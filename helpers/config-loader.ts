import { FullConfig } from './config/full';
import { IConfiguration } from './types';

export enum ConfigNames {
  Test = 'Test',
  Full = 'Full',
}

export const configNameParams = JSON.stringify(Object.values(ConfigNames));

export const loadRuntimeConfig = (configName: ConfigNames): IConfiguration => {
  switch (configName) {
    case ConfigNames.Full:
      return FullConfig;
    case ConfigNames.Test:
      return FullConfig;
    default:
      throw new Error(`Unsupported pool configuration: ${String(configName)} ${configNameParams}`);
  }
};

export const loadTestConfig = (): IConfiguration => loadRuntimeConfig(ConfigNames.Test);
