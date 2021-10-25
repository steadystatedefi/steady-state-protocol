import * as types from "../types";
import { Signer } from "ethers";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { addContractToJsonDb, getFromJsonDb } from "./deploy-db";
import { falsyOrZeroAddress } from "./runtime-utils";

interface Deployable<TArgs extends any[] = any[], TResult extends Contract = Contract> extends ContractFactory {
  deploy(...args: TArgs): Promise<TResult>;
  attach(address: string): TResult;
}

type Constructor<TDeployArgs extends any[], TResult extends Contract> = new (signer: Signer) => Deployable<TDeployArgs, TResult>;

export interface NamedDeployable<TArgs extends any[] = any[], TResult extends Contract = Contract> {
  deploy(...args: TArgs): Promise<TResult>;
  connectAndDeploy(deployer: Signer, ...args: TArgs): Promise<TResult>;
  attach(address: string): TResult;
  toString(): string;
  name(): string;

  findInstance(): (string | undefined);
  get(signer?: Signer): TResult;
}

let deployer: SignerWithAddress;

export const setDefaultDeployer = (d: SignerWithAddress) => {
  deployer = d;
}

export const getDefaultDeployer = () => {
  return deployer;
}

const wrap = <TArgs extends any[], TResult extends Contract>(f: Constructor<TArgs, TResult>): NamedDeployable<TArgs, TResult> => {
  return new class implements NamedDeployable<TArgs, TResult>{
    deploy(...args: TArgs): Promise<TResult> {
      return this.connectAndDeploy(deployer, ...args);
    }

    async connectAndDeploy(d: Signer, ...args: TArgs): Promise<TResult> {
      if (d === undefined) {
        throw new Error('deployer is required');
      }
      const name = this.name();
      const c = await new f(d).deploy(...args);
      addContractToJsonDb(name, c, name !== undefined, args);

      return c;
    }

    attach(address: string): TResult {
      return new f(deployer).attach(address);
    }

    toString(): string {
      return this.name() || 'unknown';
    }

    name(): string {
      return nameByFactory.get(this);
    }

    findInstance(): (string | undefined) {
      const name = this.name();
      return name === undefined ? undefined : getFromJsonDb(name)?.address;
    }
    
    get(signer?: Signer): TResult {
      const name = this.name();
      if (name === undefined) {
        throw new Error('instance name is unknown');
      }
      const addr = getFromJsonDb(name)?.address;
      if (falsyOrZeroAddress(addr)) {
        throw new Error('instance address is missing: ' + name);
      }
      return new f(signer || deployer).attach(addr!);
    }
  };
};

export const Factories = {
  CoveragePoolFactory: wrap(types.CoveragePoolFactory),
  PriceOracle: wrap(types.PriceOracleFactory),
}

const nameByFactory = (() => {
  const names = new Map<NamedDeployable, string>();
  Object.entries(Factories).forEach(([name, factory]) => names.set(factory, name));
  return names;
})();

export const factoryByName = (s: string): NamedDeployable => {
  return Factories[s];
};
