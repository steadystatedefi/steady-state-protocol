import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { deployTask } from '../deploy-steps';

const factory = Factories.CollateralCurrency;

// TODO make CC upgradeable

deployTask(`full:deploy-collateral-currency`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    const accessController = Factories.AccessController.get();
    const ccDetails = cfg.CollateralCurrency;

    await getOrDeploy(factory, '', [accessController.address, ccDetails.name, ccDetails.symbol]);
  })
);
