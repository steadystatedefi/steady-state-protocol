import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish, Contract } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { loadNetworkConfig } from '../../../helpers/config-loader';
import { getAssetAddress } from '../../../helpers/config-types';
import { MAX_UINT, WAD } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy, NamedDeployable } from '../../../helpers/factory-wrapper';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { falsyOrZeroAddress, mustWaitTx } from '../../../helpers/runtime-utils';
import { ProxyCatalog } from '../../../types';
import { deployTask } from '../deploy-steps';

const factory = Factories.ProxyCatalog;

deployTask(
  `full:deploy-proxy-catalog`,
  `Deploy ${factory.toString()} and default implementations`,
  __dirname
).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const accessController = Factories.AccessController.get();
    const cc = Factories.CollateralCurrency.get();

    const [proxyCatalog, newDeploy] = await getOrDeploy(factory, '', () => ({
      args: [accessController.address] as [string],
      post: async (pc: ProxyCatalog) => {
        await mustWaitTx(accessController.setAddress(AccessFlags.PROXY_FACTORY, pc.address));
      },
    }));

    const accessNamesList: string[] = [];
    const accessTypesList: string[] = [];
    const accessFlagsList: BigNumber[] = [];

    const addImpl = async <TArgs extends unknown[]>(
      typeName: string,
      f: NamedDeployable<TArgs, Contract>,
      deployArgs: TArgs,
      ctx: string,
      accessFlags?: BigNumberish
    ) => {
      const implType = formatBytes32String(typeName);
      const foundImpl = newDeploy ? '' : await proxyCatalog.getDefaultImplementation(implType, ctx);

      if (falsyOrZeroAddress(foundImpl)) {
        const [impl] = await getOrDeploy(f, '', () => ({ args: deployArgs }));
        await mustWaitTx(proxyCatalog.addAuthenticImplementation(impl.address, implType, ctx));
        await mustWaitTx(proxyCatalog.setDefaultImplementation(impl.address));
        console.log('Default implementation added:', typeName, '=', impl.address);
      } else {
        console.log('Default implementation found:', typeName, '=', foundImpl);
      }

      const flags = BigNumber.from(accessFlags ?? 0);
      if (!flags.eq(0)) {
        accessNamesList.push(typeName);
        accessTypesList.push(implType);
        accessFlagsList.push(flags);
      }
    };

    await addImpl(ProxyTypes.APPROVAL_CATALOG, Factories.ApprovalCatalogV1, [accessController.address], zeroAddress());

    const quoteTokenAddr = getAssetAddress(cfg, cfg.CollateralCurrency.quoteToken);
    await addImpl(
      ProxyTypes.ORACLE_ROUTER,
      Factories.OracleRouterV1,
      [accessController.address, quoteTokenAddr],
      zeroAddress()
    );
    await addImpl(
      ProxyTypes.COLLATERAL_FUND,
      Factories.CollateralFundV1,
      [accessController.address, cc.address, cfg.CollateralFund.fuseMask ?? 0],
      cc.address
    );
    await addImpl(
      ProxyTypes.YIELD_DISTRIBUTOR,
      Factories.YieldDistributorV1,
      [accessController.address, cc.address],
      cc.address
    );
    await addImpl(ProxyTypes.PREMIUM_FUND, Factories.PremiumFundV1, [accessController.address, cc.address], cc.address);
    await addImpl(
      ProxyTypes.INSURED_POOL,
      Factories.InsuredPoolV1,
      [accessController.address, cc.address],
      cc.address,
      MAX_UINT
    );

    {
      const unitSize = WAD;
      const args = { args: [accessController.address, unitSize, cc.address] as [string, BigNumberish, string] };

      const [ext0] = await getOrDeploy(Factories.ImperpetualPoolExtension, '', () => args);
      const [ext1] = await getOrDeploy(Factories.JoinablePoolExtension, '', () => args);

      await addImpl(
        ProxyTypes.IMPERPETUAL_INDEX_POOL,
        Factories.ImperpetualPoolV1,
        [ext0.address, ext1.address],
        cc.address
      );
    }

    if (accessTypesList) {
      console.log('Assign custom access permissions:', accessNamesList);
      await mustWaitTx(proxyCatalog.setAccess(accessTypesList, accessFlagsList));
    }
  })
);
