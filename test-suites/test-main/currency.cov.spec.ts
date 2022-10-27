import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';

import { ProtocolErrors } from '../../helpers/contract-errors';
import { Factories } from '../../helpers/contract-types';
import { MockCollateralCurrency, MockPerpetualPool } from '../../types';

import { makeSharedStateSuite, TestEnv } from './setup/make-suite';

makeSharedStateSuite('Collateral currency', (testEnv: TestEnv) => {
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  let pool: MockPerpetualPool;
  let cc: MockCollateralCurrency;
  let user: SignerWithAddress;
  let user2: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
    user2 = testEnv.users[1];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
  });

  it('Create an insurer', async () => {
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    const extension = await Factories.PerpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    pool = await Factories.MockPerpetualPool.deploy(extension.address, joinExtension.address);
  });

  it('Fails to mint/burn without a permission', async () => {
    await expect(cc.mint(user.address, unitSize * 400)).revertedWith(testEnv.covReason(ProtocolErrors.AccessDenied));
    await expect(cc.burn(user.address, unitSize * 400)).revertedWith(testEnv.covReason(ProtocolErrors.AccessDenied));
    await expect(cc.mintAndTransfer(user.address, pool.address, unitSize * 400, 0)).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );
  });

  it('Register a liquidity provider', async () => {
    await cc.registerLiquidityProvider(testEnv.deployer.address);
  });

  it('Mint', async () => {
    await cc.mint(user.address, unitSize * 400);
  });

  it('Burn', async () => {
    await cc.burn(user.address, unitSize * 200);
  });

  it('Mint and transfer to an unregistered insurer', async () => {
    const investment = unitSize * 400;
    await expect(cc.mintAndTransfer(user.address, pool.address, investment, 0, testEnv.covGas())).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );
    await expect(cc.mintAndTransfer(user2.address, user2.address, investment, 0, testEnv.covGas())).revertedWith(
      testEnv.covReason(ProtocolErrors.AccessDenied)
    );
  });

  it('Register an insurer', async () => {
    await cc.registerInsurer(pool.address);
  });

  it('Mint and transfer to a registered insurer', async () => {
    const before = await cc.balanceOf(pool.address);
    const investment = unitSize * 400;
    // totalInvested += investment;
    await cc.mintAndTransfer(user.address, pool.address, investment, 0, testEnv.covGas());

    expect(await cc.balanceOf(pool.address)).eq(before.add(investment));
    expect(await pool.balanceOf(user.address)).eq(investment);
  });

  it('Transfer to a registered insurer', async () => {
    const before = await cc.balanceOf(pool.address);
    const beforePool = await pool.balanceOf(user.address);

    const investment = unitSize * 200;
    await cc.connect(user).transfer(pool.address, investment, testEnv.covGas());

    expect(await cc.balanceOf(pool.address)).eq(before.add(investment));
    expect(await pool.balanceOf(user.address)).eq(beforePool.add(investment));
  });

  it('Unregister', async () => {
    await cc.unregister(testEnv.deployer.address);

    await expect(cc.mint(user.address, unitSize * 400)).revertedWith(testEnv.covReason(ProtocolErrors.AccessDenied));
  });
});
