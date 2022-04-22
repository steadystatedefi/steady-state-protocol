/* eslint-disable */
// TODO: enable later
import { Wallet, ContractTransaction, BigNumber } from 'ethers';
import { isAddress } from 'ethers/lib/utils';
import { isZeroAddress } from 'ethereumjs-util';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { DRE } from './dre';
import { Provider } from '@ethersproject/abstract-provider';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { eNetwork, isAutoGasNetwork, tEthereumAddress } from './types';

export const isForkNetwork = (): boolean => {
  return process.env.FORK ? true : false;
};

export const getNetworkName = (x?: string | HardhatRuntimeEnvironment): eNetwork => {
  const FORK = process.env.FORK;
  if (FORK) {
    return <eNetwork>FORK;
  }
  if (typeof x === 'string') {
    return <eNetwork>x;
  }
  if (x === undefined) {
    return <eNetwork>DRE.network.name;
  }
  return <eNetwork>x.network.name;
};

export const autoGas = (n: number, name?: string) => {
  return isAutoGasNetwork(name ?? DRE.network.name) ? undefined : n;
};

export const sleep = (milliseconds: number) => {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
};

export const createRandomAddress = () => Wallet.createRandom().address;

export const evmSnapshot = async () => await (<any>DRE).ethers.provider.send('evm_snapshot', []);

export const evmRevert = async (id: string) => (<any>DRE).ethers.provider.send('evm_revert', [id]);

export const currentTime = async () => {
  const block = await (<any>DRE).ethers.provider.getBlock('latest');
  return BigNumber.from(block.timestamp).toNumber();
};

export const advanceBlock = async (timestamp: number) => await (<any>DRE).ethers.provider.send('evm_mine', [timestamp]);

export const increaseTime = async (secondsToIncrease: number) => {
  const ethers = (<any>DRE).ethers;
  await ethers.provider.send('evm_increaseTime', [secondsToIncrease]);
  await ethers.provider.send('evm_mine', []);
};

// Workaround for time travel tests bug: https://github.com/Tonyhaenn/hh-time-travel/blob/0161d993065a0b7585ec5a043af2eb4b654498b8/test/test.js#L12
export const advanceTimeAndBlock = async function (forwardTime: number) {
  const ethers = (<any>DRE).ethers;

  const currentBlockNumber = await ethers.provider.getBlockNumber();
  const currentBlock = await ethers.provider.getBlock(currentBlockNumber);

  if (currentBlock === null) {
    /* Workaround for https://github.com/nomiclabs/hardhat/issues/1183
     */
    await ethers.provider.send('evm_increaseTime', [forwardTime]);
    await ethers.provider.send('evm_mine', []);
    //Set the next blocktime back to 15 seconds
    await ethers.provider.send('evm_increaseTime', [15]);
    return;
  }
  const currentTime = currentBlock.timestamp;
  const futureTime = currentTime + forwardTime;
  await ethers.provider.send('evm_setNextBlockTimestamp', [futureTime]);
  await ethers.provider.send('evm_mine', []);
};

export const waitForTx = async (tx: ContractTransaction) => await tx.wait(1);

export const mustWaitTx = async (ptx: Promise<ContractTransaction>) => await (await ptx).wait(1);

let skipWaitTx = false;

export const setSkipWaitTx = (v: boolean) => {
  skipWaitTx = v;
};

export const waitTx = async (ptx: Promise<ContractTransaction>): Promise<void> => {
  const tx = await ptx;
  if (!skipWaitTx) {
    await tx.wait(1);
  }
};

export const filterMapBy = (raw: { [key: string]: any }, fn: (key: string) => boolean) =>
  Object.keys(raw)
    .filter(fn)
    .reduce<{ [key: string]: any }>((obj, key) => {
      obj[key] = raw[key];
      return obj;
    }, {});

export const chunk = <T>(arr: Array<T>, chunkSize: number): Array<Array<T>> => {
  return arr.reduce(
    (prevVal: any, currVal: any, currIndx: number, array: Array<T>) =>
      !(currIndx % chunkSize) ? prevVal.concat([array.slice(currIndx, currIndx + chunkSize)]) : prevVal,
    []
  );
};

export const notFalsyOrZeroAddress = (address: tEthereumAddress | null | undefined): boolean => {
  if (!address) {
    return false;
  }
  return isAddress(address) && !isZeroAddress(address);
};

export const falsyOrZeroAddress = (address: tEthereumAddress | null | undefined): boolean => {
  return !notFalsyOrZeroAddress(address);
};

export const getSigner = (address: tEthereumAddress | string | undefined) =>
  (<any>DRE).ethers.provider.getSigner(address) as SignerWithAddress;

export const getFirstSigner = async () => (await getSigners())[0];
export const getSignerAddress = async (n: number) => (await getSigners())[n].address;
export const getSigners = async () => (await (<any>DRE).ethers.getSigners()) as SignerWithAddress[];
export const getSignerN = async (n: number) => (await getSigners())[n];

export const getContractFactory = async (abi: any[], bytecode: string) =>
  await (<any>DRE).ethers.getContractFactory(abi, bytecode);

export const getEthersProvider = () => (<any>DRE).ethers.provider as Provider;
export const createUserWallet = () => Wallet.createRandom().connect(getEthersProvider());

export const nameTags = () => (<any>DRE).tracer.nameTags;
