import { Contract } from '@ethersproject/contracts';
import { Signer } from 'ethers';

import {
  IERC20Detailed__factory as IERC20DetailedFactory,
  IInsurerPool__factory as IInsurerPoolFactory,
} from '../types';

import { getDefaultDeployer, UnnamedAttachable } from './factory-wrapper';
import { TEthereumAddress } from './types';

type ConnectFunc<TResult extends Contract> = (address: TEthereumAddress, signerOrProvider: Signer) => TResult;

const iface = <TResult extends Contract>(f: ConnectFunc<TResult>): UnnamedAttachable<TResult> =>
  new (class implements UnnamedAttachable<TResult> {
    attach(address: TEthereumAddress): TResult {
      return f(address, getDefaultDeployer());
    }
  })();

export const Ifaces = {
  IERC20: iface(IERC20DetailedFactory.connect.bind(IERC20DetailedFactory)),
  IInsurerPool: iface(IInsurerPoolFactory.connect.bind(IInsurerPoolFactory)),
};
