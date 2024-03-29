import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish } from 'ethers';

import { AccessFlags } from '../../helpers/access-flags';
import { WAD } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { currentTime } from '../../helpers/runtime-utils';
import { AccessController, MockERC20, OracleRouterV1 } from '../../types';
import { PriceSourceStruct } from '../../types/contracts/pricing/OracleRouterBase';

import { makeSuite, TestEnv } from './setup/make-suite';

enum PriceFeedType {
  StaticValue,
  ChainLinkV3,
  UniSwapV2Pair,
}

makeSuite('Pricing', (testEnv: TestEnv) => {
  let controller: AccessController;
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
    const assets: string[] = [tokenAddr];

    await user1oracle.setPriceSources(assets, prices);
    return chainlinkOracle;
  };

  const setStatic = async (tokenAddr: string, value: BigNumberish, crossAddr: string, d: number) => {
    const prices: PriceSourceStruct[] = [];
    prices.push({
      crossPrice: crossAddr,
      decimals: d,
      feedType: PriceFeedType.StaticValue,
      feedConstValue: value,
      feedContract: zeroAddress(),
    });

    const assets: string[] = [tokenAddr];

    await expect(oracle.setPriceSources(assets, prices)).to.be.reverted;
    await user1oracle.setPriceSources(assets, prices);
  };

  const checkPrice = async (tokenAddr: string, value: BigNumberish) => {
    const tokens: string[] = [tokenAddr];
    const prices = await oracle.getAssetPrices(tokens);
    {
      expect(await oracle.getAssetPrice(tokenAddr)).eq(value);
      expect(prices[0]).eq(value);
    }
  };

  function checkSource(
    source: PriceSourceStruct,
    feedType: number,
    feedContract: string,
    feedConstValue: BigNumberish,
    decimals: BigNumberish,
    crossAddr: string
  ) {
    expect(source.feedType).eq(feedType);
    expect(source.feedContract).eq(feedContract);
    expect(source.feedConstValue).eq(feedConstValue);
    expect(source.decimals).eq(decimals);
    expect(source.crossPrice).eq(crossAddr);
  }

  before(async () => {
    user1 = testEnv.users[1];
    controller = await Factories.AccessController.deploy(0);
    cc = await Factories.MockERC20.deploy('Collateral Currency', 'CC', 18);
    token = await Factories.MockERC20.deploy('Token', 'TKN', 18);
    token2 = await Factories.MockERC20.deploy('Token2', 'TKN2', 9);

    oracle = await Factories.OracleRouterV1.deploy(controller.address, cc.address);
    user1oracle = oracle.connect(user1);

    await controller.setAddress(AccessFlags.PRICE_ROUTER, oracle.address);
    await controller.grantRoles(user1.address, AccessFlags.PRICE_ROUTER_ADMIN);
  });

  it('Create oracle', async () => {
    expect(await oracle.getQuoteAsset()).eq(cc.address);
    expect(await oracle.getAssetPrice(cc.address)).eq(WAD);
  });

  it('Static price', async () => {
    const value = BigNumber.from(10).pow(17);
    await setStatic(token.address, value, zeroAddress(), 18);
    const source = await oracle.getPriceSource(token.address);

    const value2 = BigNumber.from(10).pow(9).mul(5);
    const assets = [token2.address];
    const prices = [value2];
    await user1oracle.setStaticPrices(assets, prices);
    const source2 = await oracle.getPriceSource(token2.address);

    const token3 = await Factories.MockERC20.deploy('Mock 3', 'MCK3', 9);
    await setStatic(token3.address, WAD.div(BigNumber.from(10).pow(9)), zeroAddress(), 9);

    const token4 = await Factories.MockERC20.deploy('Mock 4', 'MCK4', 27);
    await setStatic(token4.address, WAD.mul(BigNumber.from(10).pow(9)), zeroAddress(), 27);

    {
      await checkPrice(token.address, value);
      await checkPrice(token2.address, value2);
      await checkPrice(token3.address, WAD);
      await checkPrice(token4.address, WAD);
      checkSource(source, PriceFeedType.StaticValue, zeroAddress(), value, 18, zeroAddress());
      checkSource(source2, PriceFeedType.StaticValue, zeroAddress(), value2, 18, zeroAddress());

      const sources = await oracle.getPriceSources([token.address, token2.address, token3.address, token4.address]);
      checkSource(sources[0], PriceFeedType.StaticValue, zeroAddress(), value, 18, zeroAddress());
      checkSource(sources[1], PriceFeedType.StaticValue, zeroAddress(), value2, 18, zeroAddress());
      checkSource(
        sources[2],
        PriceFeedType.StaticValue,
        zeroAddress(),
        WAD.div(BigNumber.from(10).pow(9)),
        9,
        zeroAddress()
      );
      checkSource(
        sources[3],
        PriceFeedType.StaticValue,
        zeroAddress(),
        WAD.mul(BigNumber.from(10).pow(9)),
        27,
        zeroAddress()
      );
    }
  });

  it('Chainlink price', async () => {
    const value = BigNumber.from(10).pow(10);
    const chainlinkOracle = await setChainlink(token.address, value, zeroAddress());
    const source = await oracle.getPriceSource(token.address);

    {
      await checkPrice(token.address, value);
      checkSource(source, PriceFeedType.ChainLinkV3, chainlinkOracle.address, 0, 18, zeroAddress());
    }
  });

  it('Uniswap price', async () => {
    const uniswapOracle = await Factories.MockUniswapV2.deploy(token.address, cc.address);
    const value = BigNumber.from(10).pow(19);
    await uniswapOracle.setReserves(BigNumber.from(10).pow(18).mul(1000), value.mul(1000));

    const uniswapOracle2 = await Factories.MockUniswapV2.deploy(cc.address, token2.address);
    const value2 = BigNumber.from(10).pow(18).div(2);
    await uniswapOracle2.setReserves(BigNumber.from(10).pow(18).mul(200), BigNumber.from(10).pow(9).mul(400));

    const token3 = await Factories.MockERC20.deploy('Mock 3', 'MCK3', 27);
    const uniswapOracle3 = await Factories.MockUniswapV2.deploy(cc.address, token3.address);
    const value3 = BigNumber.from(10).pow(18).div(4);
    await uniswapOracle3.setReserves(BigNumber.from(10).pow(18).mul(100), BigNumber.from(10).pow(27).mul(400));

    const prices: PriceSourceStruct[] = [
      {
        crossPrice: zeroAddress(),
        decimals: 18,
        feedType: PriceFeedType.UniSwapV2Pair,
        feedConstValue: 0,
        feedContract: uniswapOracle.address,
      },
      {
        crossPrice: zeroAddress(),
        decimals: 27,
        feedType: PriceFeedType.UniSwapV2Pair,
        feedConstValue: 0,
        feedContract: uniswapOracle2.address,
      },
      {
        crossPrice: zeroAddress(),
        decimals: 9,
        feedType: PriceFeedType.UniSwapV2Pair,
        feedConstValue: 0,
        feedContract: uniswapOracle3.address,
      },
    ];
    const assets: string[] = [token.address, token2.address, token3.address];

    await user1oracle.setPriceSources(assets, prices);
    const sources = await oracle.getPriceSources(assets);

    {
      await checkPrice(token.address, value);
      await checkPrice(token2.address, value2);
      await checkPrice(token3.address, value3);
      checkSource(sources[0], PriceFeedType.UniSwapV2Pair, uniswapOracle.address, 0, 18, zeroAddress());
      checkSource(sources[1], PriceFeedType.UniSwapV2Pair, uniswapOracle2.address, 0, 27, zeroAddress());
      checkSource(sources[2], PriceFeedType.UniSwapV2Pair, uniswapOracle3.address, 0, 9, zeroAddress());
    }
  });

  it('Excessive volatility', async () => {
    const value = BigNumber.from(10).pow(10);
    const fuse = 2;
    const chainlinkOracle = await setChainlink(token.address, value, zeroAddress());
    await user1oracle.configureSourceGroup(user1.address, fuse);
    await user1oracle.attachSource(token.address, true);

    await expect(oracle.setSafePriceRanges([token.address], [value], [2000])).to.be.reverted;
    await expect(user1oracle.setSafePriceRanges([zeroAddress()], [value], [2000])).to.be.reverted;

    await user1oracle.setSafePriceRanges([token.address], [value], [2000]); // 20%
    const vals = await oracle.getPriceSourceRange(token.address);
    expect(vals.targetPrice).eq(value);
    expect(vals.tolerancePct).eq(2000);

    // Change within tolerance
    await chainlinkOracle.setAnswer(value.mul(11).div(10)); // +10%
    expect(await oracle.getAssetPrice(token.address)).eq(value.mul(11).div(10));
    expect(await oracle.callStatic.pullAssetPrice(token.address, 0)).eq(value.mul(11).div(10));
    await oracle.pullAssetPrice(token.address, fuse);
    await oracle.pullAssetPrice(token.address, fuse);

    // Trip the fuse
    await chainlinkOracle.setAnswer(value.mul(13).div(10)); // + 30%
    await oracle.pullAssetPrice(token.address, fuse);
    await expect(oracle.pullAssetPrice(token.address, fuse)).to.be.reverted;

    expect(await oracle.callStatic.pullAssetPrice(token.address, 0)).eq(0);
    expect(await oracle.getAssetPrice(token.address)).eq(value.mul(13).div(10));

    await chainlinkOracle.setAnswer(value);
    expect(await oracle.callStatic.pullAssetPrice(token.address, 0)).eq(0);
    expect(await oracle.getAssetPrice(token.address)).eq(value);
    await expect(oracle.pullAssetPrice(token.address, fuse)).to.be.reverted;

    // User1 reset the fuse
    await user1oracle.resetSourceGroup();
    await oracle.pullAssetPrice(token.address, fuse);
    await oracle.pullAssetPrice(token.address, fuse);
    expect(await oracle.getAssetPrice(token.address)).eq(value);

    await chainlinkOracle.setAnswer(value.mul(2));
    await oracle.pullAssetPrice(token.address, fuse);
    await expect(oracle.pullAssetPrice(token.address, fuse)).to.be.reverted;
    expect(await oracle.getAssetPrice(token.address)).eq(value.mul(2));

    // Admin reset the fuse
    await user1oracle.resetSourceGroupByAdmin(fuse);
    // trip the fuse again
    await oracle.pullAssetPrice(token.address, fuse);
    await expect(oracle.pullAssetPrice(token.address, fuse)).to.be.reverted;

    let groups = await oracle.groupsOf(user1.address);
    expect(groups.memberOf).eq(0);
    expect(groups.ownerOf).eq(fuse);

    groups = await oracle.groupsOf(token.address);
    expect(groups.memberOf).eq(fuse);
    expect(groups.ownerOf).eq(0);
  });

  it('Cross price', async () => {
    const value = BigNumber.from(10).pow(17);
    await setStatic(token.address, value, token.address, 18);
    expect(await oracle.getAssetPrice(token.address)).eq(value);

    await setStatic(token2.address, WAD.div(2), token.address, 18);
    expect(await oracle.getAssetPrice(token2.address)).eq(value.div(2));

    let source = await oracle.getPriceSource(token2.address);
    checkSource(source, PriceFeedType.StaticValue, zeroAddress(), WAD.div(2), 18, token.address);

    await setStatic(token2.address, WAD.mul(3), token.address, 9);
    expect(await oracle.getAssetPrice(token2.address)).eq(value.mul(3e9));

    source = await oracle.getPriceSource(token2.address);
    checkSource(source, PriceFeedType.StaticValue, zeroAddress(), WAD.mul(3), 9, token.address);

    await setStatic(token.address, value, token.address, 14);
    expect(await oracle.getAssetPrice(token.address)).eq(value.mul(1e4));
    expect(await oracle.getAssetPrice(token2.address)).eq(value.mul(3e13));
  });
});
