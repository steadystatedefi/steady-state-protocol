import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish } from 'ethers';

import { HALF_RAY, RAY } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { DRE } from '../../helpers/dre';
import { advanceTimeAndBlock } from '../../helpers/runtime-utils';
import { IInsurerPool, MockCollateralCurrency, MockImperpetualPool, MockInsuredPool } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

makeSuite.only('Imperpetual Index Pool MCD', (testEnv: TestEnv) => {
  const unitSize = 1e7; // unitSize * RATE == ratePerUnit * WAD - to give `ratePerUnit` rate points per unit per second
  const drawdownPct = 10; // 10% constant inside MockImperpetualPool
  let demanded: BigNumberish;

  let pool: MockImperpetualPool;
  let poolIntf: IInsurerPool;
  let cc: MockCollateralCurrency;
  let user: SignerWithAddress;

  const insureds: MockInsuredPool[] = [];

  const joinPool = async (riskWeightValue: number) => {
    const premiumToken = await Factories.MockERC20.deploy('PremiumToken', 'PT', 18);
    const insured = await Factories.MockInsuredPool.deploy(
      cc.address,
      1000 * unitSize,
      1e12,
      10 * unitSize,
      premiumToken.address
    );
    await pool.approveNextJoin(riskWeightValue, premiumToken.address);
    await insured.joinPool(pool.address, { gasLimit: 1000000 });

    const stats = await poolIntf.receivableDemandedCoverage(insured.address, 0);
    insureds.push(insured);
    return stats.coverage;
  };

  before(async () => {
    user = testEnv.users[0];
    cc = await Factories.MockCollateralCurrency.deploy('Collateral', '$CC');
    const joinExtension = await Factories.JoinablePoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    const extension = await Factories.ImperpetualPoolExtension.deploy(zeroAddress(), unitSize, cc.address);
    await cc.registerLiquidityProvider(testEnv.deployer.address);
    pool = await Factories.MockImperpetualPool.deploy(extension.address, joinExtension.address);
    await cc.registerInsurer(pool.address);
    poolIntf = Factories.IInsurerPool.attach(pool.address);

    demanded = BigNumber.from(0);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    demanded = demanded.add((await joinPool(10 * 100)).totalDemand);
    console.log('demanded', demanded);
  });

  it('Drawdown User Premium', async () => {
    await cc.mintAndTransfer(user.address, pool.address, demanded, 0);
    await advanceTimeAndBlock(10);

    console.log(await pool.balanceOf(user.address));
    console.log(await pool.getTotals());
  });
});
