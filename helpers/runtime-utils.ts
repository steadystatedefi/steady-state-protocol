import { Provider } from '@ethersproject/abstract-provider';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { isZeroAddress } from 'ethereumjs-util';
import { Wallet, ContractTransaction, BigNumber, ContractReceipt, ContractFactory } from 'ethers';
import { isAddress } from 'ethers/lib/utils';
import { NameTags } from 'hardhat-tracer/dist/src/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { ENetwork, isAutoGasNetwork } from './config-networks';
import { DRE } from './dre';
import { EthereumAddress } from './types';

export const isForkNetwork = (): boolean => !!process.env.FORK;

export const getNetworkName = (x?: string | HardhatRuntimeEnvironment): ENetwork => {
  const FORK = process.env.FORK;

  if (FORK) {
    return <ENetwork>FORK;
  }

  if (typeof x === 'string') {
    return <ENetwork>x;
  }

  return (x?.network?.name ?? DRE.network.name) as ENetwork;
};

export const autoGas = (num: number, name?: string): number | undefined =>
  isAutoGasNetwork(name ?? DRE.network.name) ? undefined : num;

export const sleep = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });

export const createRandomAddress = (): string => Wallet.createRandom().address;

export const evmSnapshot = async (): Promise<string> => DRE.ethers.provider.send('evm_snapshot', []) as Promise<string>;

export const evmRevert = async (id: string): Promise<unknown> => DRE.ethers.provider.send('evm_revert', [id]);

export const currentTime = async (): Promise<number> => {
  const block = await DRE.ethers.provider.getBlock('latest');

  return BigNumber.from(block.timestamp).toNumber();
};

export const advanceBlock = async (timestamp: number): Promise<unknown> =>
  DRE.ethers.provider.send('evm_mine', [timestamp]);

export const increaseTime = async (secondsToIncrease: number): Promise<void> => {
  const { ethers } = DRE;
  await ethers.provider.send('evm_increaseTime', [secondsToIncrease]);
  await ethers.provider.send('evm_mine', []);
};

// Workaround for time travel tests bug: https://github.com/Tonyhaenn/hh-time-travel/blob/0161d993065a0b7585ec5a043af2eb4b654498b8/test/test.js#L12
export const advanceTimeAndBlock = async (forwardTime: number): Promise<void> => {
  const { ethers } = DRE;

  const currentBlockNumber = await ethers.provider.getBlockNumber();
  const currentBlock = await ethers.provider.getBlock(currentBlockNumber);

  if (currentBlock === null) {
    /* Workaround for https://github.com/nomiclabs/hardhat/issues/1183
     */
    await ethers.provider.send('evm_increaseTime', [forwardTime]);
    await ethers.provider.send('evm_mine', []);
    // Set the next blocktime back to 15 seconds
    await ethers.provider.send('evm_increaseTime', [15]);
    return;
  }

  const time = currentBlock.timestamp;
  const futureTime = time + forwardTime;
  await ethers.provider.send('evm_setNextBlockTimestamp', [futureTime]);
  await ethers.provider.send('evm_mine', []);
};

export const waitForTx = async (tx: ContractTransaction): Promise<ContractReceipt> => tx.wait(1);

export const mustWaitTx = async (ptx: Promise<ContractTransaction>): Promise<ContractReceipt> =>
  ptx.then((tx) => tx.wait(1));

let skipWaitTx = false;

export const setSkipWaitTx = (canSkip: boolean): void => {
  skipWaitTx = canSkip;
};

export const waitTx = async (ptx: Promise<ContractTransaction>): Promise<void> => {
  const tx = await ptx;

  if (!skipWaitTx) {
    await tx.wait(1);
  }
};

export const filterMapBy = (
  raw: Record<string, unknown>,
  predicate: (key: string) => boolean
): Record<string, unknown> =>
  Object.keys(raw)
    .filter(predicate)
    .reduce<Record<string, unknown>>((acc, key) => {
      acc[key] = raw[key];

      return acc;
    }, {});

export const chunk = <T>(arr: Array<T>, chunkSize: number): Array<Array<T>> =>
  arr.reduce(
    (prevVal: T[][], _: T, currIndx: number, array: Array<T>) =>
      !(currIndx % chunkSize) ? prevVal.concat([array.slice(currIndx, currIndx + chunkSize)]) : prevVal,
    []
  );

export const notFalsyOrZeroAddress = (address: EthereumAddress | null | undefined): boolean => {
  if (!address) {
    return false;
  }
  return isAddress(address) && !isZeroAddress(address);
};

export const ensureValidAddress = (address: string | undefined | null, msg?: string): string => {
  if (notFalsyOrZeroAddress(address)) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    return address!;
  }
  throw new Error(`Wrong address: ${msg ?? ''} "${address ?? ''}"`);
};

export const falsyOrZeroAddress = (address: EthereumAddress | null | undefined): boolean =>
  !notFalsyOrZeroAddress(address);

export const getSigner = (address?: EthereumAddress | string): SignerWithAddress =>
  DRE.ethers.provider.getSigner(address) as unknown as SignerWithAddress;

export const getFirstSigner = async (): Promise<SignerWithAddress> => {
  const [signer] = await getSigners();

  return signer;
};

export const getSignerAddress = async (n: number): Promise<EthereumAddress | undefined> => {
  const signers = await getSigners();

  return signers[n]?.address;
};

export async function getSigners(): Promise<SignerWithAddress[]> {
  return DRE.ethers.getSigners();
}

export const getNthSigner = async (n: number): Promise<SignerWithAddress | undefined> => {
  const signers = await getSigners();

  return signers[n];
};

export const getContractFactory = async (abi: unknown[], bytecode: string): Promise<ContractFactory> =>
  DRE.ethers.getContractFactory(abi, bytecode);

export const getEthersProvider = (): Provider => DRE.ethers.provider as Provider;

export const createUserWallet = (): Wallet => Wallet.createRandom().connect(getEthersProvider());

export const nameTags = (): NameTags => DRE.tracer.nameTags;
