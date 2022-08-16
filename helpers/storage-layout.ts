import { Table } from 'console-table-printer';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import fs from 'fs';

export interface StorageLayoutVariable {
  name: string;
  slot: string;
  offset: number;
  type: string;
}

export interface ContractStorageLayout {
  name: string;
  stateVariables: StorageLayoutVariable[];
}

export function isInheritedStorageLayout(parent: ContractStorageLayout, child: ContractStorageLayout): boolean {
  const pVars = parent.stateVariables;
  const cVars = child.stateVariables;
  if (cVars.length < pVars.length) {
    return false;
  }

  return !pVars.some((p, i) => {
    const c = cVars[i];
    return p.name !== c.name || p.slot !== c.slot || p.offset !== c.offset || p.type !== c.type;
  });
}

export function tabulateContractLayouts(contracts: ContractStorageLayout[]): Table {
  const p = new Table({
    columns: [
      { name: 'contract', alignment: 'left' },
      { name: 'state_variable', alignment: 'left' },
      { name: 'storage_slot', alignment: 'center' },
      { name: 'offset', alignment: 'center' },
      { name: 'type', alignment: 'left' },
    ],
  });

  for (const contract of contracts) {
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

  return p;
}

/* eslint-disable @typescript-eslint/no-unsafe-member-access,@typescript-eslint/no-unsafe-assignment */

export async function extractContractLayout(
  env: HardhatRuntimeEnvironment,
  names: string[]
): Promise<ContractStorageLayout[]> {
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

    if (!contracts) {
      return [];
    }
  }

  const buildInfoPaths = await env.artifacts.getBuildInfoPaths();
  const contractLayouts: ContractStorageLayout[] = [];

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

      const contract: ContractStorageLayout = { name: contractName, stateVariables: [] };
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
