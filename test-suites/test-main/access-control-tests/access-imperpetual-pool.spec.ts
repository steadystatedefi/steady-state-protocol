import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';

import { AccessFlags } from '../../../helpers/access-flags';
import { MAX_UINT } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, setInsurer, State } from './setup';

makeSuite('access: Imperpetual Pool', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;

  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  const params: WeightedPoolParamsStruct = {
    maxAdvanceUnits: 100_000_000,
    minAdvanceUnits: 1_000,
    riskWeightTarget: 10_00,
    minInsuredSharePct: 1_00,
    maxInsuredSharePct: 100_00,
    minUnitsPerRound: 10,
    maxUnitsPerRound: 20,
    overUnitsPerRound: 30,
    coveragePrepayPct: 100_00,
    maxUserDrawdownPct: 0,
    unitsPerAutoPull: 0,
  };

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    user3 = testEnv.users[3];
    state = await deployAccessControlState(deployer);

    await setInsurer(state, deployer, user2.address);

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN | AccessFlags.LP_DEPLOY);
    await state.cc.registerInsurer(state.insurer.address);
    await state.controller.revokeRoles(deployer.address, AccessFlags.INSURER_ADMIN);
  });

  it('ROLE: Governor', async () => {
    await state.insured.joinPool(state.insurer.address);
    await expect(state.insurer.approveJoiner(state.insured.address, true)).to.be.reverted;
    await expect(state.insurer.setPoolParams(params)).to.be.reverted;

    await state.insurer.connect(user2).approveJoiner(state.insured.address, true);
    await state.insurer.connect(user2).setPoolParams(params);
  });

  it('ROLE: Insurer Ops', async () => {
    const ext = Factories.ImperpetualPoolExtension.attach(state.insurer.address);
    await state.insured.joinPool(state.insurer.address);

    await expect(state.insurer.approveJoiner(state.insured.address, true)).reverted;
    await expect(state.insurer.addSubrogation(user2.address, 0)).reverted;
    await expect(ext.cancelCoverageDemand(state.insured.address, 0, MAX_UINT)).reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_OPS);
    await state.insurer.approveJoiner(state.insured.address, true);
    await state.insurer.addSubrogation(user2.address, 0);

    // await state.insured.pushCoverageDemandTo(state.insurer.address, 11);

    // await ext.cancelCoverageDemand(state.insured.address, 1, MAX_UINT);
    // onlyActiveInsuredOrOps
  });

  it('ROLE: Insurer Admin', async () => {
    await expect(state.insurer.connect(user3).setGovernor(user3.address)).to.be.reverted;
    await expect(state.insurer.connect(user3).setPremiumDistributor(user3.address)).to.be.reverted;
    await expect(state.insurer.connect(user3).setPoolParams(params)).to.be.reverted;

    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.insurer.setGovernor(user3.address);
    await state.insurer.setPremiumDistributor(user3.address);
    await state.insurer.setPoolParams(params);
  });

  it('ROLE: Collateral Currency', async () => {
    await state.controller.grantRoles(deployer.address, AccessFlags.INSURER_ADMIN);
    await state.cc.registerLiquidityProvider(deployer.address);

    await expect(state.insurer.onTransferReceived(user2.address, user2.address, 100, '')).to.be.reverted;
    await state.cc.mintAndTransfer(user2.address, user2.address, 100, 100);
  });

  // TODO: ImperpetualPoolBase onlySelf

  // TODO: WeightedPoolBase OnlyPremiumDistributor
});
