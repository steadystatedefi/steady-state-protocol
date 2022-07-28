import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish } from 'ethers';

import { MAX_UINT, WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { currentTime } from '../../helpers/runtime-utils';
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
  let token2: MockERC20;
  let oracle: OracleRouterV1;
  let user1: SignerWithAddress;
  let user1oracle: OracleRouterV1;

  const setChainlink = async (tokenAddr: string, value: BigNumberish, crossAddr: string) => {
    const chainlinkOracle = await Factories.MockChainlinkV3.deploy();
    await chainlinkOracle.setAnswer(value);
    await chainlinkOracle.setUpdatedAt(await currentTime());

    const prices: PriceSourceStruct[] = [];
    prices.push({
      crossPrice: crossAddr,
      decimals: 18,
      feedType: PriceFeedType.ChainLinkV3,
      feedConstValue: 0,
      feedContract: chainlinkOracle.address,
    });
    const assets: string[] = [];
    assets.push(tokenAddr);

    await user1oracle.setPriceSources(assets, prices);
    return chainlinkOracle;
  };

  const setStatic = async (tokenAddr: string, value: BigNumberish, crossAddr: string) => {
    const prices: PriceSourceStruct[] = [];
    prices.push({
      crossPrice: crossAddr,
      decimals: 18,
      feedType: PriceFeedType.StaticValue,
      feedConstValue: value,
      feedContract: zeroAddress(),
    });

    const assets: string[] = [];
    assets.push(tokenAddr);

    await expect(oracle.setPriceSources(assets, prices)).to.be.reverted;
    await user1oracle.setPriceSources(assets, prices);
  };

  before(async () => {
    user1 = testEnv.users[1];
    controller = await Factories.AccessController.deploy(SINGLETS, ROLES, PROTECTED_SINGLETS);
    proxyCatalog = await Factories.ProxyCatalog.deploy(controller.address);
    approvalCatalog = await Factories.ApprovalCatalogV1.deploy(controller.address);
    cc = await Factories.MockERC20.deploy('Collateral Currency', 'CC', 18);
    token = await Factories.MockERC20.deploy('Token', 'TKN', 18);
    token2 = await Factories.MockERC20.deploy('Token2', 'TKN2', 9);

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
    const value = BigNumber.from(10).pow(17);
    await setStatic(token.address, value, zeroAddress());
    expect(await oracle.getAssetPrice(token.address)).eq(value);
  });

  it('Chainlink price', async () => {
    const value = BigNumber.from(10).pow(10);
    const chainlinkOracle = await setChainlink(token.address, value, zeroAddress());
    expect(await oracle.getAssetPrice(token.address)).eq(value);
  });

  it('Uniswap price', async () => {
    const uniswapOracle = await Factories.MockUniswapV2.deploy(token.address, cc.address);
    const value = BigNumber.from(10).pow(19);
    await uniswapOracle.setReserves(BigNumber.from(10).pow(18).mul(1000), value.mul(1000));

    const prices: PriceSourceStruct[] = [];
    prices.push({
      crossPrice: zeroAddress(),
      decimals: 18,
      feedType: PriceFeedType.UniSwapV2Pair,
      feedConstValue: 0,
      feedContract: uniswapOracle.address,
    });
    const assets: string[] = [];
    assets.push(token.address);

    await user1oracle.setPriceSources(assets, prices);
    expect(await oracle.getAssetPrice(token.address)).eq(value);
  });

  it('Excessive volatility', async () => {
    const value = BigNumber.from(10).pow(10);
    const fuse = 2 ** 1;
    const chainlinkOracle = await setChainlink(token.address, value, zeroAddress());
    await user1oracle.registerSourceGroup(user1.address, fuse, true);
    await user1oracle.attachSource(token.address, true);

    await expect(oracle.setPriceSourceRange(token.address, value, 800)).to.be.reverted;
    await expect(user1oracle.setPriceSourceRange(zeroAddress(), value, 800)).to.be.reverted;

    await user1oracle.setPriceSourceRange(token.address, value, 2000); // 20%
    await chainlinkOracle.setAnswer(value.mul(11).div(10)); // +10%
    await oracle.pullAssetPrice(token.address, fuse);

    await chainlinkOracle.setAnswer(value.mul(13).div(10)); // + 30%
    await oracle.pullAssetPrice(token.address, fuse);
    await expect(oracle.pullAssetPrice(token.address, fuse)).to.be.reverted;
    await chainlinkOracle.setAnswer(value);
    await expect(oracle.pullAssetPrice(token.address, fuse)).to.be.reverted;
  });

  /*
  it('Cross price', async() => {

  });
  */
});
