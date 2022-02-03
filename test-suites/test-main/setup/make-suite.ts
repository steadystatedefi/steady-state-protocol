import chai from 'chai';
import bignumberChai from 'chai-bignumber';
import { almostEqual } from './almost-equal';
import { solidity } from 'ethereum-waffle';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { evmRevert, evmSnapshot, getSigners } from '../../../helpers/runtime-utils';

chai.use(bignumberChai());
chai.use(almostEqual());
chai.use(solidity);

export interface TestEnv {
  deployer: SignerWithAddress;
  users: SignerWithAddress[];
  underCoverage: boolean;
  // Declare TestEnv variables
}

let snapshotId: string = '0x1';
const setSnapshotId = (id: string) => {
  snapshotId = id;
};

const testEnv: TestEnv = {
  deployer: {} as SignerWithAddress,
  users: [] as SignerWithAddress[],
} as TestEnv;

export async function initializeMakeSuite(underCoverage: boolean) {
  [testEnv.deployer, ...testEnv.users] = await getSigners();
  testEnv.underCoverage = underCoverage;

  // Set TestEnv variables
}

const setHead = async () => {
  setSnapshotId(await evmSnapshot());
};

const revertHead = async () => {
  await evmRevert(snapshotId);
};

export function makeSharedStateSuite(name: string, tests: (testEnv: TestEnv) => void) {
  describe(name, () => {
    before(async () => {
      await setHead();
    });
    tests(testEnv);
    after(async () => {
      await revertHead();
    });
  });
}

export function makeSuite(name: string, tests: (testEnv: TestEnv) => void) {
  describe(name, () => {
    beforeEach(async () => {
      await setHead();
    });
    tests(testEnv);
    afterEach(async () => {
      await revertHead();
    });
  });
}
