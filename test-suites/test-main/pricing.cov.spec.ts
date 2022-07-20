import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber } from 'ethers';

import { MAX_UINT, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { AccessController, ApprovalCatalogV1, MockERC20, OracleRouterV1, ProxyCatalog } from '../../types';
import { PriceSourceStruct } from '../../types/contracts/pricing/OracleRouterBase';

import { makeSuite, TestEnv } from './setup/make-suite';

const ROLES = MAX_UINT.mask(16);
const SINGLETS = MAX_UINT.mask(64).xor(ROLES);
const PROTECTED_SINGLETS = MAX_UINT.mask(26).xor(ROLES);

const PRICE_ROUTER_ADMIN = BigNumber.from(1).shl(7);
const PRICE_ROUTER = BigNumber.from(1).shl(29);

enum PriceFeedType {
  StaticValue,
  ChainLinkV3,
  UniSwapV2Pair,
}

makeSuite.only('Pricing', (testEnv: TestEnv) => {
  let controller: AccessController;
  let proxyCatalog: ProxyCatalog;
  let approvalCatalog: ApprovalCatalogV1;
  let cc: MockERC20;
  let token: MockERC20;
  let oracle: OracleRouterV1;
  let user1: SignerWithAddress;
  let user1oracle: OracleRouterV1;

  before(async () => {
    user1 = testEnv.users[1];
    controller = await Factories.AccessController.deploy(SINGLETS, ROLES, PROTECTED_SINGLETS);
    proxyCatalog = await Factories.ProxyCatalog.deploy(controller.address);
    approvalCatalog = await Factories.ApprovalCatalogV1.deploy(controller.address);
    cc = await Factories.MockERC20.deploy('Collateral Currency', 'CC', 18);
    token = await Factories.MockERC20.deploy('Token', 'TKN =---', 18);

    oracle = await Factories.OracleRouterV1.deploy(controller.address, cc.address);
    user1oracle = oracle.connect(user1);

    await controller.setAddress(PRICE_ROUTER, oracle.address);
    await controller.grantRoles(user1.address, PRICE_ROUTER_ADMIN);
  });

  it('Create oracle', async () => {
    expect(await oracle.getQuoteAsset()).eq(cc.address);
    expect(await oracle.getAssetPrice(cc.address)).eq(WAD);
  });

  it('Static price', async () => {
    const prices: PriceSourceStruct[] = [];
    prices.push({
      crossPrice: zeroAddress(),
      decimals: 18,
      feedType: PriceFeedType.StaticValue,
      feedConstValue: BigNumber.from(10).pow(17),
      feedContract: zeroAddress(),
    });

    const assets: string[] = [];
    assets.push(token.address);

    await expect(oracle.setPriceSources(assets, prices)).to.be.reverted;
    await user1oracle.setPriceSources(assets, prices);
    console.log(await oracle.getAssetPrice(token.address));
  });
});
