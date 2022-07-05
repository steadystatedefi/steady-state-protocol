import { Contract } from '@ethersproject/contracts';
import { Signer } from 'ethers';

import * as types from '../types';

import { getDefaultDeployer, UnnamedAttachable } from './factory-wrapper';
import { tEthereumAddress } from './types';

type ConnectFunc<TResult extends Contract> = (address: tEthereumAddress, signerOrProvider: Signer) => TResult;

const iface = <TResult extends Contract>(f: ConnectFunc<TResult>): UnnamedAttachable<TResult> =>
  new (class implements UnnamedAttachable<TResult> {
    attach(address: tEthereumAddress): TResult {
      return f(address, getDefaultDeployer());
    }
  })();

/* eslint-disable @typescript-eslint/unbound-method */
export const Ifaces = {
  IERC20: iface(types.IERC20Detailed__factory.connect),
  IInsurerPool: iface(types.IInsurerPool__factory.connect),
};
/* eslint-enable @typescript-eslint/unbound-method */
