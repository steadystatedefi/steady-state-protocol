import { IRuntimeConfig } from "./types";

export enum ConfigNames {
  Test = 'Test',
  Full = 'Full'
}

export const loadTestConfig = () => loadRuntimeConfig(ConfigNames.Test);

export const loadRuntimeConfig = (configName: ConfigNames): (IRuntimeConfig | undefined) => {
  switch (configName) {
    case ConfigNames.Full:
      return undefined;
    case ConfigNames.Test:
      return undefined;
    //   return TestConfig;
    default:
      throw new Error(`Unsupported pool configuration: ${configName} ${Object.values(ConfigNames)}`);
  }
};
