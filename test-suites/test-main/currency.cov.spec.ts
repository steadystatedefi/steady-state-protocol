/* eslint-disable */
// TODO: enable later
import { makeSharedStateSuite, TestEnv } from './setup/make-suite';
import { Factories } from '../../helpers/contract-types';
import { CollateralCurrency, MockInsuredPool, MockWeightedPool } from '../../types';
import { expect } from 'chai';
import { advanceTimeAndBlock, createRandomAddress, currentTime } from '../../helpers/runtime-utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { zeroAddress } from 'ethereumjs-util';

makeSharedStateSuite('Collateral currency', (testEnv: TestEnv) => {
  const decimals = 18;
  const RATE = 1e12; // this is about a max rate (0.0001% per s) or 3150% p.a
  const premiumPerUnit = 10;
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const poolDemand = 100000 * unitSize;
  let pool: MockWeightedPool;
  let insureds: MockInsuredPool[] = [];
  let cc: CollateralCurrency;
  let user: SignerWithAddress;

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.CollateralCurrency.deploy('Collateral', '$CC', 18);
  });

  it('Create an insurer', async () => {
    const extension = await Factories.WeightedPoolExtension.deploy(unitSize);
    pool = await Factories.MockWeightedPool.deploy(cc.address, unitSize, decimals, extension.address);
  });

  it('Fails to mint/burn without a permission', async () => {
    await expect(cc.mint(user.address, unitSize * 400)).revertedWith(''); // TODO access denied error
    await expect(cc.burn(user.address, unitSize * 400)).revertedWith(''); // TODO access denied error
    await expect(cc.mintAndTransfer(user.address, pool.address, unitSize * 400)).revertedWith(''); // TODO access denied error
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

  it('Mint and transfer to an unregistered insusrer', async () => {
    const investment = unitSize * 400;
    // totalInvested += investment;
    await cc.mintAndTransfer(user.address, pool.address, investment, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    expect(await cc.balanceOf(pool.address)).eq(investment);
    expect(await pool.balanceOf(user.address)).eq(0); // doesnt react
  });

  it('Register an insurer', async () => {
    await cc.registerInsurer(pool.address);
  });

  it('Mint and transfer to a registered insusrer', async () => {
    const before = await cc.balanceOf(pool.address);
    const investment = unitSize * 400;
    // totalInvested += investment;
    await cc.mintAndTransfer(user.address, pool.address, investment, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    expect(await cc.balanceOf(pool.address)).eq(before.add(investment));
    expect(await pool.balanceOf(user.address)).eq(investment);
  });

  it('Transfer to a registered insusrer', async () => {
    const before = await cc.balanceOf(pool.address);
    const beforePool = await pool.balanceOf(user.address);

    const investment = unitSize * 200;
    await cc.connect(user).transfer(pool.address, investment, {
      gasLimit: testEnv.underCoverage ? 2000000 : undefined,
    });

    expect(await cc.balanceOf(pool.address)).eq(before.add(investment));
    expect(await pool.balanceOf(user.address)).eq(beforePool.add(investment));
  });

  it('Unregister', async () => {
    await cc.unregister(testEnv.deployer.address);

    await expect(cc.mint(user.address, unitSize * 400)).revertedWith(''); // TODO access denied error
  });
});
