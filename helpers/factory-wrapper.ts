import { Contract, ContractFactory } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Signer } from 'ethers';

import { addContractToJsonDb, getFromJsonDb } from './deploy-db';
import { falsyOrZeroAddress } from './runtime-utils';
import { tEthereumAddress } from './types';

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

export interface UnnamedAttachable<TResult extends Contract = Contract> {
  attach(address: string): TResult;
}

export interface NamedGettable<TResult extends Contract = Contract> extends Named {
  attach(address: string): TResult;
  get(signer?: Signer, name?: string): TResult;
  findInstance(name?: string): string | undefined;
}

export interface NamedDeployable<DeployArgs extends unknown[] = unknown[], TResult extends Contract = Contract>
  extends NamedGettable<TResult> {
  deploy(...args: DeployArgs): Promise<TResult>;
  connectAndDeploy(deployer: Signer, deployName: string, args: DeployArgs): Promise<TResult>;
}

let deployer: SignerWithAddress;

export const setDefaultDeployer = (d: SignerWithAddress): void => {
  deployer = d;
};

export const getDefaultDeployer = (): SignerWithAddress => deployer;

const nameByFactory = new Map<NamedDeployable, string>();

export const wrapFactory = <TArgs extends unknown[], TResult extends Contract>(
  F: FactoryConstructor<TArgs, TResult>,
  mock: boolean
): NamedDeployable<TArgs, TResult> =>
  new (class implements NamedDeployable<TArgs, TResult> {
    deploy(...args: TArgs): Promise<TResult> {
      return this.connectAndDeploy(deployer, '', args);
    }

    async connectAndDeploy(d: Signer, deployName: string, args: TArgs): Promise<TResult> {
      if (d === undefined) {
        throw new Error('deployer is required');
      }
      const name = deployName || this.name();
      const c = await new F(d).deploy(...args);
      addContractToJsonDb(name || 'unknown', c, name !== undefined, args);

      return c;
    }

    attach(address: string): TResult {
      return new F(deployer).attach(address);
    }

    toString(): string {
      return this.name() || 'unknown';
    }

    name(): string | undefined {
      return nameByFactory.get(this);
    }

    findInstance(name?: string): string | undefined {
      // TODO: get rid of side effect
      // eslint-disable-next-line no-param-reassign
      name = name ?? this.name();

      return name !== undefined ? getFromJsonDb<{ address: tEthereumAddress }>(name)?.address : undefined;
    }

    get(signer?: Signer, name?: string): TResult {
      // TODO: get rid of side effect
      // eslint-disable-next-line no-param-reassign
      name = name ?? this.name();

      if (name === undefined) {
        throw new Error('instance name is unknown');
      }

      const address = getFromJsonDb<{ address: tEthereumAddress }>(name)?.address;

      if (falsyOrZeroAddress(address)) {
        throw new Error(`instance address is missing: ${name}`);
      }

      return new F(signer || deployer).attach(address);
    }

    isMock(): boolean {
      return mock ?? false;
    }
  })();

export const wrap = <TArgs extends unknown[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>
): NamedDeployable<TArgs, TResult> => wrapFactory(f, false);

export const mock = <TArgs extends unknown[], TResult extends Contract>(
  f: FactoryConstructor<TArgs, TResult>
): NamedDeployable<TArgs, TResult> => wrapFactory(f, true);

export const addNamedDeployable = (f: NamedDeployable, name: string): typeof nameByFactory =>
  nameByFactory.set(f, name);
