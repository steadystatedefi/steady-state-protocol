import { IRuntimeConfig } from "./types";

export enum ConfigNames {
  Test = 'Test',
  Full = 'Full'
}

export const loadRuntimeConfig = (configName: ConfigNames): IRuntimeConfig => {
  switch (configName) {
    // case ConfigNames.Test:
    //   return TestConfig;
    default:
      throw new Error(`Unsupported pool configuration: ${Object.values(ConfigNames)}`);
  }
};
