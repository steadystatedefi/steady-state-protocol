import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, BigNumberish, Contract } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { loadNetworkConfig } from '../../../helpers/config-loader';
import { getAssetAddress } from '../../../helpers/config-types';
import { MAX_UINT } from '../../../helpers/constants';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy, NamedDeployable } from '../../../helpers/factory-wrapper';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { falsyOrZeroAddress, mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';
import { assignRole, findOrDeployProxyFromCatalog } from '../templates';

const factory = Factories.ProxyCatalog;
const factoryCC = Factories.CollateralCurrencyV1;

deployTask(
  `full:deploy-proxy-catalog`,
  `Deploy ${factory.toString()} and ${factoryCC.toString()}`,
  __dirname
).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const accessController = Factories.AccessController.get();
    const [proxyCatalog, newDeploy] = await getOrDeploy(factory, '', [accessController.address]);

    await assignRole(AccessFlags.PROXY_FACTORY, proxyCatalog.address, newDeploy, accessController);

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
        const [impl] = await getOrDeploy(f, '', deployArgs);
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

    await addImpl(ProxyTypes.COLLATERAL_CCY, Factories.CollateralCurrencyV1, [accessController.address], zeroAddress());

    const ccDetails = cfg.CollateralCurrency;
    const [cc] = await findOrDeployProxyFromCatalog(
      factoryCC,
      ProxyTypes.COLLATERAL_CCY,
      factoryCC.interface.encodeFunctionData('initializeCollateralCurrency', [ccDetails.name, ccDetails.symbol]),
      '',
      zeroAddress()
    );

    await addImpl(
      ProxyTypes.COLLATERAL_FUND,
      Factories.CollateralFundV1,
      [accessController.address, cc.address, cfg.CollateralFund.fuseMask ?? 0],
      cc.address
    );
    await addImpl(ProxyTypes.REINVESTOR, Factories.ReinvestorV1, [accessController.address, cc.address], cc.address);
    await addImpl(ProxyTypes.PREMIUM_FUND, Factories.PremiumFundV1, [accessController.address, cc.address], cc.address);
    await addImpl(
      ProxyTypes.INSURED_POOL,
      Factories.InsuredPoolV1,
      [accessController.address, cc.address],
      cc.address,
      MAX_UINT
    );

    {
      const unitSize = cfg.Commons.unitSize;
      const args = [accessController.address, unitSize, cc.address] as [string, BigNumberish, string];

      const [ext0] = await getOrDeploy(Factories.ImperpetualPoolExtension, '', args);
      const [ext1] = await getOrDeploy(Factories.JoinablePoolExtension, '', args);

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
