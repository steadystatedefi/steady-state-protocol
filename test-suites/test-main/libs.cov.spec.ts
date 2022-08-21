import { expect } from 'chai';

import { MAX_UINT, MAX_UINT128 } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { MockLibs } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite('Strings library', (testEnv: TestEnv) => {
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

  it('overflow revert type', async () => {
    await expect(libs.testOverflowUint128Mutable(MAX_UINT128.add(1))).revertedWith('panic code 0x11');
    await expect(libs.testOverflowUint128Mutable(MAX_UINT)).revertedWith('panic code 0x11');
  });

  it('overflowUint128', async () => {
    expect(await libs.testOverflowUint128(0)).eq(0);
    expect(await libs.testOverflowUint128(MAX_UINT128)).eq(MAX_UINT128);
  });

  it('overflowBits', async () => {
    await libs.testOverflowBits(0, 0);
    await libs.testOverflowBits(MAX_UINT, 256);
    await libs.testOverflowBits(MAX_UINT128, 128);

    await expect(libs.testOverflowBits(MAX_UINT, 255)).reverted;
    await expect(libs.testOverflowBits(MAX_UINT128.add(1), 128)).reverted;
    await expect(libs.testOverflowBits(1, 0)).reverted;
  });

  // it('overflowAdd', async () => {
  //   await libs.testOverflowAdd(0, 0);
  //   await libs.testOverflowAdd(MAX_UINT, 0);
  //   await libs.testOverflowAdd(MAX_UINT, MAX_UINT);
  //   await libs.testOverflowAdd(MAX_UINT, MAX_UINT.sub(1));
  //   await libs.testOverflowAdd(MAX_UINT128, 0);
  //   await libs.testOverflowAdd(MAX_UINT128, MAX_UINT128);
  //   await libs.testOverflowAdd(MAX_UINT128, MAX_UINT128.sub(1));

  //   await expect(libs.testOverflowAdd(MAX_UINT128, MAX_UINT128.add(1))).reverted;
  //   await expect(libs.testOverflowAdd(MAX_UINT128, MAX_UINT)).reverted;
  // });
});
