/* eslint-disable */
// TODO: enable later
import { Signer } from 'ethers';
import { Contract, ContractFactory } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { addContractToJsonDb, getFromJsonDb } from './deploy-db';
import { falsyOrZeroAddress } from './runtime-utils';

interface Deployable<TArgs extends any[] = any[], TResult extends Contract = Contract> extends ContractFactory {
  attach(address: string): TResult;
  deploy(...args: TArgs): Promise<TResult>;
}

type FactoryConstructor<TDeployArgs extends any[], TResult extends Contract> = new (signer: Signer) => Deployable<
  TDeployArgs,
  TResult
>;

interface Named {
  toString(): string;
  name(): string | undefined;
  isMock(): boolean;
}

export interface UnnamedAttachable<TResult extends Contract = Contract> {
  attach(address: string): TResult;
}

export interface NamedGettable<TResult extends Contract = Contract> extends Named {
  attach(address: string): TResult;
  get(signer?: Signer, name?: string): TResult;
  findInstance(name?: string): string | undefined;
}

export interface NamedDeployable<DeployArgs extends any[] = any[], TResult extends Contract = Contract>
  extends NamedGettable<TResult> {
  deploy(...args: DeployArgs): Promise<TResult>;
  connectAndDeploy(deployer: Signer, deployName: string, args: DeployArgs): Promise<TResult>;
}

let deployer: SignerWithAddress;

export const setDefaultDeployer = (d: SignerWithAddress) => {
  deployer = d;
};

export const getDefaultDeployer = () => {
  return deployer;
};

export const wrapFactory = <TArgs extends any[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>,
  mock: boolean
): NamedDeployable<TArgs, TResult> => {
  return new (class implements NamedDeployable<TArgs, TResult> {
    deploy(...args: TArgs): Promise<TResult> {
      return this.connectAndDeploy(deployer, '', args);
    }

    async connectAndDeploy(d: Signer, deployName: string, args: TArgs): Promise<TResult> {
      if (d === undefined) {
        throw new Error('deployer is required');
      }
      const name = deployName || this.name();
      const c = await new f(d).deploy(...args);
      addContractToJsonDb(name || 'unknown', c, name !== undefined, args);

      return c;
    }

    attach(address: string): TResult {
      return new f(deployer).attach(address);
    }

    toString(): string {
      return this.name() || 'unknown';
    }

    name(): string | undefined {
      return nameByFactory.get(this);
    }

    findInstance(name?: string): string | undefined {
      name = name ?? this.name();
      return name === undefined ? undefined : getFromJsonDb(name)?.address;
    }

    get(signer?: Signer, name?: string): TResult {
      name = name ?? this.name();
      if (name === undefined) {
        throw new Error('instance name is unknown');
      }
      const addr = getFromJsonDb(name)?.address;
      if (falsyOrZeroAddress(addr)) {
        throw new Error('instance address is missing: ' + name);
      }
      return new f(signer || deployer).attach(addr!);
    }

    isMock(): boolean {
      return mock ?? false;
    }
  })();
};

export const wrap = <TArgs extends any[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>
): NamedDeployable<TArgs, TResult> => wrapFactory(f, false);
export const mock = <TArgs extends any[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>
): NamedDeployable<TArgs, TResult> => wrapFactory(f, true);

const nameByFactory = new Map<NamedDeployable, string>();

export const addNamedDeployable = (f: NamedDeployable, name: string) => nameByFactory.set(f, name);
