import { Contract } from '@ethersproject/contracts';
import { Signer } from 'ethers';

import {
  IERC20Detailed__factory as IERC20DetailedFactory,
  IInsurerPool__factory as IInsurerPoolFactory,
} from '../types';

import { getDefaultDeployer, UnnamedAttachable } from './factory-wrapper';
import { tEthereumAddress } from './types';

type ConnectFunc<TResult extends Contract> = (address: tEthereumAddress, signerOrProvider: Signer) => TResult;

const iface = <TResult extends Contract>(f: ConnectFunc<TResult>): UnnamedAttachable<TResult> =>
  new (class implements UnnamedAttachable<TResult> {
    attach(address: tEthereumAddress): TResult {
      return f(address, getDefaultDeployer());
    }
  })();

export const Ifaces = {
  /* eslint-disable @typescript-eslint/unbound-method */
  IERC20: iface(IERC20DetailedFactory.connect),
  IInsurerPool: iface(IInsurerPoolFactory.connect),
  /* eslint-enable @typescript-eslint/unbound-method */
};
