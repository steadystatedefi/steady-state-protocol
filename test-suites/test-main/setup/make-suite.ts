import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai from 'chai';
import bignumberChai from 'chai-bignumber';
import { solidity } from 'ethereum-waffle';

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
}

let snapshotId = '0x1';
const setSnapshotId = (id: string) => {
  snapshotId = id;
};

const testEnv: TestEnv = {
  deployer: {} as SignerWithAddress,
  users: [] as SignerWithAddress[],
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
