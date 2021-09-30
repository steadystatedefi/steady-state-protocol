import { makeSuite, TestEnv } from './setup/make-suite';
import { createRandomAddress } from '../../helpers/runtime-utils';

makeSuite('ExampleSuite', (testEnv: TestEnv) => {
  it('Example test', async () => {
    const { users } = testEnv;
    const mockAddress = createRandomAddress();
  });
});
