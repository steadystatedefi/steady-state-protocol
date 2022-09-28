import { expect } from 'chai';
import { BigNumber } from 'ethers';

import { MAX_UINT, MAX_UINT128, MAX_UINT144 } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { BalancerCalcConfig } from '../../helpers/types-balancer';
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
    if (testEnv.underCoverage) {
      return;
    }
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

  it('encode CalcConfigValue', async () => {
    const u64 = BigNumber.from('0x0102030405060708');
    const u32 = BigNumber.from('0xF1E1C1B1');
    expect(await libs.testCalcConfigValue(MAX_UINT144, u64, u32, 0xc0fe)).eq(
      BalancerCalcConfig.encodeRaw(MAX_UINT144, u64, u32, 0xc0fe)
    );
  });
});
