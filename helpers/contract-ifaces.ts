import { Contract } from '@ethersproject/contracts';
import { Signer } from 'ethers';
import { Interface } from 'ethers/lib/utils';

import * as types from '../types';

import { ExtractInterface, getDefaultDeployer, UnnamedAttachable } from './factory-wrapper';
import { tEthereumAddress } from './types';

interface InterfaceFactory<TResult extends Contract> {
  connect(address: tEthereumAddress, signerOrProvider: Signer): TResult;
  createInterface(): Interface;
}

const iface = <TResult extends Contract>(F: InterfaceFactory<TResult>): UnnamedAttachable<TResult> =>
  new (class implements UnnamedAttachable<TResult> {
    readonly interface = F.createInterface() as ExtractInterface<TResult>;

    attach(address: tEthereumAddress): TResult {
      return F.connect(address, getDefaultDeployer());
    }
  })();

export const Ifaces = {
  IERC20: iface(types.IERC20Detailed__factory),
  IInsurerPool: iface(types.IInsurerPool__factory),
};
