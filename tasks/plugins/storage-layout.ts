import { Table } from 'console-table-printer';
import { extendConfig, task } from 'hardhat/config';
import { HardhatConfig, HardhatRuntimeEnvironment } from 'hardhat/types';

import fs from 'fs';

// A much faster version of hardhat-storage-layout. Supports filtering.

task('storage-layout', 'Print storage layout of contracts')
  .addOptionalVariadicPositionalParam('contracts', 'Names of contracts')
  .setAction(async ({ contracts }, DRE: HardhatRuntimeEnvironment) => {
    const layouts = await exportStorageLayout(DRE, contracts as string[]);
    const prettifier = new Prettify(layouts);
    prettifier.tabulate();
  });

/* eslint-disable @typescript-eslint/no-unsafe-member-access,@typescript-eslint/no-unsafe-call,@typescript-eslint/no-unsafe-assignment */

extendConfig((config: HardhatConfig) => {
  for (const compiler of config.solidity.compilers) {
    compiler.settings ??= {};
    compiler.settings.outputSelection ??= {};
    compiler.settings.outputSelection['*'] ??= {};
    compiler.settings.outputSelection['*']['*'] ??= [];

    const outputs = compiler.settings.outputSelection['*']['*'];
    if (!outputs.includes('storageLayout')) {
      outputs.push('storageLayout');
    }
  }
});

async function exportStorageLayout(env: HardhatRuntimeEnvironment, names: string[]): Promise<Row[]> {
  const contracts: { sourceName: string; contractName: string }[] = [];

  const filters: Set<string> = new Set();
  (names ?? []).forEach((name) => filters.add(name));

  {
    const fullyQualifiedNames = await env.artifacts.getAllFullyQualifiedNames();
    for (const fullName of fullyQualifiedNames) {
      const { sourceName, contractName } = await env.artifacts.readArtifact(fullName);
      if (filters.size === 0 || filters.has(contractName) || filters.has(fullName)) {
        contracts.push({ sourceName, contractName });
      }
    }
  }

  const buildInfoPaths = await env.artifacts.getBuildInfoPaths();
  const contractLayouts: Row[] = [];

  for (const artifactPath of buildInfoPaths) {
    const artifact: Buffer = fs.readFileSync(artifactPath);
    const artifactJsonABI = JSON.parse(artifact.toString());

    for (const { sourceName, contractName } of contracts) {
      try {
        if (!artifactJsonABI.output.contracts[sourceName][contractName]) {
          continue;
        }
      } catch (e) {
        continue;
      }

      const contract: Row = { name: contractName, stateVariables: [] };
      for (const stateVariable of artifactJsonABI.output.contracts[sourceName][contractName].storageLayout.storage) {
        contract.stateVariables.push({
          name: stateVariable.label,
          slot: stateVariable.slot,
          offset: stateVariable.offset,
          type: stateVariable.type,
        });
      }
      contractLayouts.push(contract);
    }
  }

  return contractLayouts;
}

interface StateVariable {
  name: string;
  slot: string;
  offset: number;
  type: string;
}

interface Row {
  name: string;
  stateVariables: StateVariable[];
}

class Prettify {
  public table: Row[];

  constructor(data: Row[]) {
    this.table = data;
  }

  public get(): Row[] {
    return this.table;
  }

  public tabulate() {
    if (!this.table.length) {
      console.error('Table has empty feilds');
    } else {
      const p = new Table({
        columns: [
          { name: 'contract', alignment: 'left' },
          { name: 'state_variable', alignment: 'left' },
          { name: 'storage_slot', alignment: 'center' },
          { name: 'offset', alignment: 'center' },
          { name: 'type', alignment: 'left' },
        ],
      });

      try {
        for (const contract of this.table) {
          for (const stateVariable of contract.stateVariables) {
            p.addRow({
              contract: contract.name,
              state_variable: stateVariable.name,
              storage_slot: stateVariable.slot,
              offset: stateVariable.offset,
              type: stateVariable.type,
            });
          }
        }
        p.printTable();
      } catch (e) {
        console.log(e); // TODO HRE error handler
      }
    }
  }
}
