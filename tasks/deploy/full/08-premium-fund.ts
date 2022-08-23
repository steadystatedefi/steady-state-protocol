import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { deployTask } from '../deploy-steps';
import { findOrDeployProxyFromCatalog } from '../templates';

const catalogName = ProxyTypes.PREMIUM_FUND;

deployTask(`full:deploy-premium-fund`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const factory = Factories.PremiumFundV1;
    const initFunctionData = factory.interface.encodeFunctionData('initializePremiumFund');

    await findOrDeployProxyFromCatalog(factory, catalogName, initFunctionData);
  })
);
