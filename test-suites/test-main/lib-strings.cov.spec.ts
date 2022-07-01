import { expect } from 'chai';

import { Factories } from '../../helpers/contract-types';
import { MockLibs } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Test libraries', (testEnv: TestEnv) => {
  let libs: MockLibs;

  before(async () => {
    libs = await Factories.MockLibs.deploy();
  });

  it('asString(bytes32)', async () => {
    expect(await libs.testBytes32ToString('0x0000000000000000000000000000000000000000000000000000000000000000')).eq('');
    if (testEnv.underCoverage) {
      return;
    }
    expect(await libs.testBytes32ToString('0x3031323334353637383930313233343536373839303132333435363738390000')).eq(
      '012345678901234567890123456789'
    );
    expect(await libs.testBytes32ToString('0x3031323334353637383930313233343536373839303132333435363738392020')).eq(
      '012345678901234567890123456789'
    );
    expect(await libs.testBytes32ToString('0x2020303132333435363738393031323334353637383930313233343536373839')).eq(
      '  012345678901234567890123456789'
    );
    expect(await libs.testBytes32ToString('0x0000303132333435363738393031323334353637383930313233343536373839')).eq(
      '\u0000\u0000012345678901234567890123456789'
    );
  });
});
