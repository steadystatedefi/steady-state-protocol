import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai from 'chai';
import bignumberChai from 'chai-bignumber';
import { solidity } from 'ethereum-waffle';
import { BigNumberish, CallOverrides } from 'ethers';

import { evmRevert, evmSnapshot, getSigners } from '../../../helpers/runtime-utils';

import { almostEqual } from './almost-equal';

// eslint-disable-next-line @typescript-eslint/no-unsafe-argument,@typescript-eslint/no-unsafe-call
chai.use(bignumberChai());
chai.use(almostEqual());
chai.use(solidity);
chai.config.includeStack = true;

export interface TestEnv {
  deployer: SignerWithAddress;
  users: SignerWithAddress[];
  underCoverage: boolean;
  // Declare TestEnv variables

  covGas(gasLimit?: BigNumberish | Promise<BigNumberish>, overrides?: CallOverrides): CallOverrides;
  covReason(reason: string): string;
}

let snapshotId = '0x1';
const setSnapshotId = (id: string) => {
  snapshotId = id;
};

const testEnv: TestEnv = {
  deployer: {} as SignerWithAddress,
  users: [] as SignerWithAddress[],
  covGas(gasLimit?: BigNumberish | Promise<BigNumberish>, overrides?: CallOverrides): CallOverrides {
    if (!this.underCoverage) {
      return overrides ?? {};
    }
    if ((gasLimit ?? 0) === 0) {
      gasLimit = 2000000; // eslint-disable-line no-param-reassign
    }
    if (overrides === undefined) {
      return { gasLimit };
    }
    overrides.gasLimit = gasLimit; // eslint-disable-line no-param-reassign
    return overrides;
  },
  covReason(reason: string): string {
    // NB! Ganache doesnt support custom errors
    return this.underCoverage ? 'revert' : reason;
  },
} as TestEnv;

export async function initializeMakeSuite(underCoverage: boolean): Promise<void> {
  [testEnv.deployer, ...testEnv.users] = await getSigners();
  testEnv.underCoverage = underCoverage;

  // Set TestEnv variables
}

export const setSuiteState = async (): Promise<void> => {
  setSnapshotId(await evmSnapshot());
};

export const revertSuiteState = async (): Promise<void> => {
  await evmRevert(snapshotId);
};

interface SuiteFunction {
  (title: string, fn: (testEnv: TestEnv) => void): Mocha.Suite | void;
}

interface IMakeSuite extends SuiteFunction {
  only: SuiteFunction;
  skip: SuiteFunction;
}

function isolatedState(tests: (this: Mocha.Suite, testEnv: TestEnv) => void): (this: Mocha.Suite) => void {
  return function isolatedStateFn(this: Mocha.Suite): void {
    this.beforeEach(async () => {
      await setSuiteState();
    });

    tests.call(this, testEnv);

    this.afterEach(async () => {
      await revertSuiteState();
    });
  };
}

function sharedState(tests: (this: Mocha.Suite, testEnv: TestEnv) => void): (this: Mocha.Suite) => void {
  return function sharedStateFn(this: Mocha.Suite): void {
    before(async () => {
      await setSuiteState();
    });

    tests.call(this, testEnv);

    after(async () => {
      await revertSuiteState();
    });
  };
}

interface SuiteStateFunc {
  (tests: (this: Mocha.Suite, testEnv: TestEnv) => void): (this: Mocha.Suite) => void;
}

function makeSuiteMaker(stateFn: SuiteStateFunc): IMakeSuite {
  const result = ((title: string, fn: (testEnv: TestEnv) => void) => describe(title, stateFn(fn))) as IMakeSuite;
  result.only = (title: string, fn: (testEnv: TestEnv) => void) => describe.only(title, stateFn(fn));
  result.skip = (title: string, fn: (testEnv: TestEnv) => void) => describe.skip(title, stateFn(fn));

  return result;
}

export const makeSuite = makeSuiteMaker(isolatedState);

export const makeSharedStateSuite = makeSuiteMaker(sharedState);
