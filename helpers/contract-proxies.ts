import { Contract, Overrides } from '@ethersproject/contracts';
import { Signer, BytesLike } from 'ethers';
import { FunctionFragment, Interface } from 'ethers/lib/utils';

import { getDefaultDeployer, NamedDeployable, NamedGettable } from './factory-wrapper';

type DeployableProxy = NamedDeployable<
  [admin: string, logic: string, data: BytesLike, overrides?: Overrides],
  Contract
>;

interface EncodeFunctionInterface<T extends FunctionFragment | string, V extends ReadonlyArray<unknown>>
  extends Interface {
  encodeFunctionData(functionFragment: T, values?: V): string;
}

class EncodedFunctionContract<T extends FunctionFragment | string, V extends ReadonlyArray<unknown>> extends Contract {
  readonly interface!: EncodeFunctionInterface<T, V>;
}

let proxyImplFactory: DeployableProxy;

export const setProxyImpl = (proxyImpl: DeployableProxy): void => {
  proxyImplFactory = proxyImpl;
};

// TODO: refactoring
// eslint-disable-next-line no-return-assign
export const nameOfProxy = (factory: NamedGettable, proxyName: string): string =>
  // eslint-disable-next-line no-param-reassign
  !proxyName || proxyName[0] === '-' ? (proxyName = factory.toString() + (proxyName || '-PROXY')) : proxyName;

export const deployProxy = async <
  T extends FunctionFragment | string,
  V extends ReadonlyArray<unknown>,
  R extends EncodedFunctionContract<T, V>
>(
  proxyAdmin: string,
  factory: NamedGettable<R>,
  proxyName: string,
  functionFragment?: T,
  values?: V
): Promise<R> => {
  const impl = factory.get();
  const encoded = functionFragment ? impl.interface.encodeFunctionData(functionFragment, values) : '';
  const proxied = await proxyImplFactory.connectAndDeploy(getDefaultDeployer(), nameOfProxy(factory, proxyName), [
    proxyAdmin,
    impl.address,
    encoded,
  ]);
  return factory.attach(proxied.address);
};

export const findProxy = <R extends Contract>(factory: NamedGettable<R>, proxyName: string): string | undefined =>
  factory.findInstance(nameOfProxy(factory, proxyName));

export const getProxy = <R extends Contract>(factory: NamedGettable<R>, proxyName: string, signer?: Signer): R =>
  factory.get(signer, nameOfProxy(factory, proxyName));
