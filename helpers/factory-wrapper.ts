import { Contract, ContractFactory, Overrides } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Signer } from 'ethers';
import { Interface } from 'ethers/lib/utils';

import { addContractToJsonDb, getAddrFromJsonDb } from './deploy-db';
import { falsyOrZeroAddress, waitForTx } from './runtime-utils';
import { EthereumAddress } from './types';

interface Deployable<TArgs extends unknown[] = unknown[], TResult extends Contract = Contract> extends ContractFactory {
  attach(address: string): TResult;
  deploy(...args: TArgs): Promise<TResult>;
}

type FactoryConstructor<TDeployArgs extends unknown[], TResult extends Contract> = new (signer: Signer) => Deployable<
  TDeployArgs,
  TResult
>;

interface Named {
  toString(): string;
  name(): string | undefined;
  isMock(): boolean;
}

class ContractInterface<I extends Interface> extends Contract {
  readonly interface!: I;
}

export type ExtractInterface<T extends ContractInterface<Interface>> = T extends ContractInterface<infer I> ? I : never;

export interface UnnamedAttachable<TResult extends Contract = Contract> {
  interface: ExtractInterface<TResult>;
  attach(address: string): TResult;
}

export interface NamedAttachable<TResult extends Contract = Contract> extends UnnamedAttachable<TResult>, Named {}

export interface NamedGettable<TResult extends Contract = Contract> extends NamedAttachable<TResult> {
  get(signer?: Signer | null, name?: string): TResult;
  findInstance(name?: string): string | undefined;
}

export interface NamedDeployable<DeployArgs extends unknown[] = unknown[], TResult extends Contract = Contract>
  extends NamedGettable<TResult> {
  deploy(...args: DeployArgs): Promise<TResult>;
  connectAndDeploy(deployer: Signer | null, deployName: string, args: DeployArgs): Promise<TResult>;
}

let deployer: SignerWithAddress;
let blockMocks = false;

export const setDefaultDeployer = (d: SignerWithAddress): void => {
  deployer = d;
};

export const getDefaultDeployer = (): SignerWithAddress => deployer;

export const setBlockMocks = (block: boolean): void => {
  blockMocks = block;
};

export const wrapContractFactory = <TArgs extends unknown[], TResult extends Contract>(
  F: FactoryConstructor<TArgs, TResult>,
  mock: boolean
): NamedDeployable<TArgs, TResult> =>
  new (class implements NamedDeployable<TArgs, TResult> {
    readonly interface = (F as unknown as InterfaceFactory<TResult>).createInterface();

    deploy(...args: TArgs): Promise<TResult> {
      return this.connectAndDeploy(deployer, '', args);
    }

    private checkMocks() {
      if (blockMocks && mock) {
        throw new Error(`Mocks are not allowed: ${this.toString()}`);
      }
    }

    async connectAndDeploy(d: Signer | null, deployName: string, args: TArgs): Promise<TResult> {
      this.checkMocks();

      const dd = d || deployer;
      if (!dd) {
        throw new Error('deployer is required');
      }
      const name = deployName || this.name();
      const c = await new F(dd).deploy(...args);
      addContractToJsonDb(name || 'unknown', c, this.name() ?? '', name !== undefined, args);

      return c;
    }

    attach(address: string): TResult {
      this.checkMocks();

      if (falsyOrZeroAddress(address)) {
        throw new Error(`Unable to attach ${this.toString()}: ${address}`);
      }
      return new F(deployer).attach(address);
    }

    toString(): string {
      return this.name() || 'unknown';
    }

    name(): string | undefined {
      return getNameByFactory(this);
    }

    findInstance(n?: string): string | undefined {
      if (blockMocks && mock) {
        return undefined;
      }

      const name = n || this.name();
      return name !== undefined ? getAddrFromJsonDb(name) : undefined;
    }

    get(signer?: Signer | null, name?: string): TResult {
      this.checkMocks();

      // eslint-disable-next-line no-param-reassign
      name = name ?? this.name();
      if (name === undefined) {
        throw new Error('instance name is unknown');
      }

      const address = getAddrFromJsonDb(name);
      if (falsyOrZeroAddress(address)) {
        throw new Error(`instance address is missing: ${name}`);
      }

      return new F(signer || deployer).attach(address);
    }

    isMock(): boolean {
      return mock ?? false;
    }
  })();

const nameByFactory = new Map<Named, string>();

export const loadFactories = (catalog: Record<string, NamedAttachable>): void => {
  Object.entries(catalog).forEach(([n, f]) => nameByFactory.set(f, n));
};

function getNameByFactory(f: Named): string | undefined {
  return nameByFactory.get(f);
}

export type ExcludeOverrides<T extends unknown[]> = T extends [...infer Head, Overrides?] ? Head : T;

export async function getOrDeploy<TArgs extends unknown[], T extends Contract>(
  f: NamedDeployable<TArgs, T>,
  n: string,
  deployArgs: TArgs
): Promise<[T, boolean]> {
  const pre = f.findInstance(n);
  const logName = n || f.toString();
  if (pre !== undefined) {
    console.log(`Already deployed ${logName}:`, pre);
    return [f.attach(pre), false];
  }
  const deployed = await f.connectAndDeploy(deployer, n, deployArgs);

  await waitForTx(deployed.deployTransaction);
  console.log(`${logName}:`, deployed.address);
  return [deployed, true];
}

interface InterfaceFactory<TResult extends Contract> {
  connect(address: EthereumAddress, signerOrProvider: Signer): TResult;
  createInterface(): ExtractInterface<TResult>;
}

export const wrapInterfaceFactory = <TResult extends Contract>(
  F: InterfaceFactory<TResult>
): NamedAttachable<TResult> =>
  new (class implements NamedAttachable<TResult> {
    readonly interface = F.createInterface();

    attach(address: EthereumAddress): TResult {
      return F.connect(address, getDefaultDeployer());
    }

    toString(): string {
      return this.name() || 'unknown';
    }

    name(): string | undefined {
      return getNameByFactory(this);
    }

    isMock(): boolean {
      return false;
    }
  })();

export const wrap = <TArgs extends unknown[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>
): NamedDeployable<TArgs, TResult> => wrapContractFactory(f, false);

export const mock = <TArgs extends unknown[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>
): NamedDeployable<TArgs, TResult> => wrapContractFactory(f, true);

export const iface = wrapInterfaceFactory;
