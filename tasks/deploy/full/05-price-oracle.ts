import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { loadNetworkConfig } from '../../../helpers/config-loader';
import { getAssetAddress, IPriceStatic } from '../../../helpers/config-types';
import { ZERO } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { PriceFeedType, ProxyTypes } from '../../../helpers/proxy-types';
import { falsyOrZeroAddress, mustWaitTx, notFalsyOrZeroAddress, waitForTx } from '../../../helpers/runtime-utils';
import { EthereumAddress } from '../../../helpers/types';
import { PriceSourceStruct } from '../../../types/contracts/pricing/OracleRouterBase';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog } from './templates';

const catalogName = ProxyTypes.ORACLE_ROUTER;

deployTask(`full:deploy-price-oracle`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);
    const factory = Factories.OracleRouterV1;

    const accessController = Factories.AccessController.get();
    const accessFlag = AccessFlags.PRICE_ROUTER;

    const found = await accessController.getAddress(accessFlag);
    if (notFalsyOrZeroAddress(found)) {
      console.log(`Already deployed: ${found}`);
      return;
    }

    const initFunctionData = factory.interface.encodeFunctionData('initializePriceOracle');
    const addr = await deployProxyFromCatalog(catalogName, initFunctionData, '', zeroAddress());

    await waitForTx(await accessController.setAddress(accessFlag, addr));

    const assetAddrs: string[] = [];
    const assetInfos: PriceSourceStruct[] = [];

    for (const [assetName, feedInfo] of Object.entries(cfg.PriceFeeds)) {
      if (!feedInfo) {
        continue;
      }
      const assetAddr = getAssetAddress(cfg, assetName);

      let feedContract: EthereumAddress = '';
      let feedType: number;
      if ('value' in feedInfo) {
        if (ZERO.eq(feedInfo.value)) {
          throw new Error(`Constant price can not be zero: ${assetName}`);
        }
        feedContract = zeroAddress();
        feedType = PriceFeedType.StaticValue;
      } else {
        feedContract = feedInfo.source ?? '';

        if (typeof feedInfo.sourceType === 'number') {
          feedType = feedInfo.sourceType;
        } else {
          switch (feedInfo.sourceType) {
            case 'chainlink':
              feedType = PriceFeedType.ChainLinkV3;
              break;
            case 'uniswap2':
              feedType = PriceFeedType.UniSwapV2Pair;
              if (!feedContract) {
                feedContract = await findUniSwapV2Pair(assetAddr, cfg.Dependencies.UniswapV2Router);
              }
              break;
            default:
              throw new Error(`Unknown feed source type: ${assetName}`);
          }
        }
        if (falsyOrZeroAddress(feedContract)) {
          throw new Error(`Feed source address is required for the feed type: ${assetName}, ${feedInfo.sourceType}`);
        }
      }

      let crossPrice: EthereumAddress;
      if (feedInfo.xPrice === true) {
        crossPrice = assetAddr;
      } else {
        crossPrice = feedInfo.xPrice ? getAssetAddress(cfg, feedInfo.xPrice) : zeroAddress();
      }

      assetAddrs.push(assetAddr);
      assetInfos.push({
        feedType,
        feedContract,
        feedConstValue: (feedInfo as IPriceStatic).value ?? 0,
        decimals: feedInfo.decimals,
        crossPrice,
      });
    }

    if (assetAddrs.length === 0) {
      return;
    }

    const router = Factories.OracleRouterV1.attach(addr);

    const filteredAssetAddrs: string[] = [];
    const filteredAssetInfos: PriceSourceStruct[] = [];

    (await router.getPriceSources(assetAddrs)).forEach((v, i) => {
      if (v.feedType === 0 && ZERO.eq(v.feedConstValue)) {
        filteredAssetAddrs.push(assetAddrs[i]);
        filteredAssetInfos.push(assetInfos[i]);
      }
    });

    if (filteredAssetAddrs.length === 0) {
      return;
    }

    await mustWaitTx(router.setPriceSources(filteredAssetAddrs, filteredAssetInfos));
  })
);

// eslint-disable-next-line @typescript-eslint/require-await
async function findUniSwapV2Pair(
  assetAddr: EthereumAddress,
  UniswapV2Router?: EthereumAddress
): Promise<EthereumAddress> {
  if (!UniswapV2Router || falsyOrZeroAddress(UniswapV2Router)) {
    return '';
  }

  throw new Error(`Not implemented`);
}
