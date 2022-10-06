import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { MAX_UINT, WAD } from '../../../helpers/constants';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, setInsurer, State } from './setup';

makeSuite('access: Reinvestor', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    state = await deployAccessControlState(deployer);

    await state.premToken.approve(state.strat.address, MAX_UINT);
    await state.premToken.approve(state.reinvestor.address, MAX_UINT);

    await setInsurer(state, deployer, user2.address);
    await state.controller.grantRoles(
      deployer.address,
      AccessFlags.LP_ADMIN | AccessFlags.LP_DEPLOY | AccessFlags.BORROWER_ADMIN
    );
    await state.cc.registerLiquidityProvider(state.fund.address);
    await state.fund.addAsset(state.premToken.address, zeroAddress());
    await state.fund.setSpecialRoles(deployer.address, 1); // APPROVED_DEPOSIT
    await state.fund.invest(deployer.address, state.premToken.address, WAD, state.insurer.address);
    await state.reinvestor.enableStrategy(state.strat.address, true);
    await state.controller.revokeRoles(
      deployer.address,
      AccessFlags.LP_ADMIN | AccessFlags.LP_DEPLOY | AccessFlags.BORROWER_ADMIN
    );
  });

  it('ROLE: Borrower Admin', async () => {
    await expect(state.reinvestor.enableStrategy(state.strat.address, false)).reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.BORROWER_ADMIN);
    await state.reinvestor.enableStrategy(state.strat.address, false);
  });

  /// borrowOps is either LP_ADMIN or LIQUIDITY_MANAGER
  it('ROLE: Liquidity Manager', async () => {
    await expect(state.reinvestor.pushTo(state.premToken.address, state.fund.address, state.strat.address, 1e10))
      .reverted;
    await state.controller.grantRoles(deployer.address, AccessFlags.LIQUIDITY_MANAGER);
    await state.reinvestor.pushTo(state.premToken.address, state.fund.address, state.strat.address, 1e10);
    await state.controller.revokeRoles(deployer.address, AccessFlags.LIQUIDITY_MANAGER);

    await state.strat.deltaYield(state.premToken.address, 1e4);
    {
      await expect(
        state.reinvestor.pullYieldFrom(state.premToken.address, state.strat.address, state.fund.address, 1e4)
      ).reverted;
      await expect(state.reinvestor.pullFrom(state.premToken.address, state.strat.address, state.fund.address, 1e5))
        .reverted;
      await expect(
        state.reinvestor.repayLossFrom(
          state.premToken.address,
          deployer.address,
          state.strat.address,
          state.fund.address,
          1e5
        )
      ).reverted;
    }

    await state.controller.grantRoles(deployer.address, AccessFlags.LIQUIDITY_MANAGER);
    {
      await state.reinvestor.pullYieldFrom(state.premToken.address, state.strat.address, state.fund.address, 1e4);
      await state.reinvestor.pullFrom(state.premToken.address, state.strat.address, state.fund.address, 1e5);
      await state.reinvestor.repayLossFrom(
        state.premToken.address,
        deployer.address,
        state.strat.address,
        state.fund.address,
        1e5
      );
    }
  });

  it('ROLE: LP Admin', async () => {
    await expect(state.reinvestor.pushTo(state.premToken.address, state.fund.address, state.strat.address, 1e10))
      .reverted;
    await state.controller.grantRoles(deployer.address, AccessFlags.LP_ADMIN);
    await state.reinvestor.pushTo(state.premToken.address, state.fund.address, state.strat.address, 1e10);
    await state.controller.revokeRoles(deployer.address, AccessFlags.LP_ADMIN);
  });

  it('ROLE: onlyCollateralFund', async () => {
    await state.controller.grantRoles(deployer.address, AccessFlags.LIQUIDITY_MANAGER);
    {
      await expect(state.reinvestor.pushTo(state.premToken.address, user2.address, state.strat.address, 1e10)).reverted;
      await expect(state.reinvestor.pullYieldFrom(state.premToken.address, state.strat.address, user2.address, 1e4))
        .reverted;
      await expect(
        state.reinvestor.repayLossFrom(
          state.premToken.address,
          deployer.address,
          state.strat.address,
          user2.address,
          1e5
        )
      ).reverted;
    }
  });
});
