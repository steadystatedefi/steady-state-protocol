import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { WAD } from '../../../helpers/constants';
import { PriceSourceStruct } from '../../../types/contracts/pricing/OracleRouter';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, State } from './setup';

makeSuite('access: Oracle Router', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;
  let user2: SignerWithAddress;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    state = await deployAccessControlState(deployer);
  });

  it('ROLE: Oracle Admin', async () => {
    const source: PriceSourceStruct = {
      feedType: 1,
      crossPrice: zeroAddress(),
      decimals: 18,
      feedConstValue: WAD,
      feedContract: user2.address,
    };

    {
      await expect(state.oracle.setStaticPrices([state.premToken.address], [WAD.add(1)])).reverted;
      await expect(state.oracle.setPriceSources([state.premToken.address], [source])).reverted;
      await expect(state.oracle.setSafePriceRanges([state.premToken.address], [WAD], [2000])).reverted;
      await expect(state.oracle.resetSourceGroupByAdmin(1)).reverted;
      await expect(state.oracle.configureSourceGroup(user2.address, 1)).reverted;
    }

    await state.controller.grantRoles(deployer.address, AccessFlags.PRICE_ROUTER_ADMIN);
    {
      await state.oracle.setStaticPrices([state.premToken.address], [WAD.add(1)]);
      await state.oracle.setPriceSources([state.premToken.address], [source]);
      await state.oracle.setSafePriceRanges([state.premToken.address], [WAD], [2000]);
      await state.oracle.resetSourceGroupByAdmin(1);
      await state.oracle.configureSourceGroup(user2.address, 1);
    }
  });
});
