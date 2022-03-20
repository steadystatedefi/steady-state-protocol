import { Signer } from "ethers";
import { Contract, Overrides } from "@ethersproject/contracts";
import { FunctionFragment, Interface } from "ethers/lib/utils";
import { getDefaultDeployer, NamedDeployable, NamedGettable } from "./factory-wrapper";
import { BytesLike } from "ethers";

interface DeployableProxy extends 
    NamedDeployable<[    admin: string,
        logic: string,
        data: BytesLike,
        overrides?: Overrides
    ], Contract> {}

interface EncodeFunctionInterface<T extends FunctionFragment | string, V extends ReadonlyArray<any>> extends Interface {
  encodeFunctionData(functionFragment: T, values?: V): string
}

class EncodedFunctionContract<T extends FunctionFragment | string, V extends ReadonlyArray<any>> extends Contract {
  readonly interface!: EncodeFunctionInterface<T, V>;
}

let proxyImplFactory: DeployableProxy;

export const setProxyImpl = (proxyImpl: DeployableProxy) => {
    proxyImplFactory = proxyImpl;
}

export const nameOfProxy = (factory: NamedGettable, proxyName: string) => {
    return !proxyName || proxyName[0] == '-' ?
        proxyName = factory.toString() + (proxyName || '-PROXY')
    : proxyName;
}

export const deployProxy = async <T extends FunctionFragment | string, V extends ReadonlyArray<any>,
    R extends EncodedFunctionContract<T, V>>(
    proxyAdmin: string, factory: NamedGettable<R>, proxyName: string, functionFragment?: T, values?: V): Promise<R> => 
{
    const impl = factory.get();
    const encoded = functionFragment ? impl.interface.encodeFunctionData(functionFragment, values) : '';
    const proxied = await proxyImplFactory.connectAndDeploy(
        getDefaultDeployer(), 
        nameOfProxy(factory, proxyName), 
        [proxyAdmin, impl.address, encoded]);
    return factory.attach(proxied.address);
}

export const findProxy = <R extends Contract>(factory: NamedGettable<R>, proxyName: string) => {
    return factory.findInstance(nameOfProxy(factory, proxyName));
}

export const getProxy = <R extends Contract>(factory: NamedGettable<R>, proxyName: string, signer?: Signer) => {
    return factory.get(signer, nameOfProxy(factory, proxyName));
}
