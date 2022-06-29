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

export function makeSharedStateSuite(name: string, tests: (testEnv: TestEnv) => void): void {
  describe(name, () => {
    before(async () => {
      await setSuiteState();
    });

    tests(testEnv);

    after(async () => {
      await revertSuiteState();
    });
  });
}

export function makeSuite(name: string, tests: (testEnv: TestEnv) => void): void {
  describe(name, () => {
    beforeEach(async () => {
      await setSuiteState();
    });

    tests(testEnv);

    afterEach(async () => {
      await revertSuiteState();
    });
  });
}
