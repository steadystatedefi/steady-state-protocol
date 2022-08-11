import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { getOrDeploy } from '../../../helpers/factory-wrapper';
import { deployTask } from '../deploy-steps';

const factory = Factories.CollateralCurrency;

// TODO make CC upgradeable

deployTask(`full:deploy-collateral-currency`, `Deploy ${factory.toString()}`, __dirname).setAction(
  dreAction(() =>
    getOrDeploy(factory, '', () => {
      const accessController = Factories.AccessController.get();

      return {
        args: [accessController.address, 'Collateral Currency', 'CC'] as [string, string, string],
      };
    })
  )
);
