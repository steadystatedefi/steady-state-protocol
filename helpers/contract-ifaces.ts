import { Signer } from "ethers";
import { Contract } from "@ethersproject/contracts";
import { getDefaultDeployer, UnnamedAttachable } from "./factory-wrapper";
import { IERC20DetailedFactory } from "../types/IERC20DetailedFactory";
import { IInsurerPoolFactory } from "../types/IInsurerPoolFactory";

type ConnectFunc<TResult extends Contract> = (address: string, signerOrProvider: Signer) => TResult;

const iface = <TResult extends Contract>(f: ConnectFunc<TResult>): UnnamedAttachable<TResult> => {
  return new class implements UnnamedAttachable<TResult>{
    attach(address: string): TResult {
      return f(address, getDefaultDeployer());
    }
  };
};

export const Ifaces = {
  IERC20: iface(IERC20DetailedFactory.connect),
  IInsurerPool: iface(IInsurerPoolFactory.connect),
}

