import { Signer } from "ethers";
import { Contract } from "@ethersproject/contracts";
import { IERC20DetailedFactory } from "../types/IERC20DetailedFactory";
import { getDefaultDeployer } from "./contract-types";

export interface UnnamedAttachable<TResult extends Contract = Contract> {
  attach(address: string): TResult;
}

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
}

