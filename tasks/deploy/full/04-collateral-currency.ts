import { Factories } from '../../../helpers/contract-types';
import { falsyOrZeroAddress, getFirstSigner, waitForTx } from '../../../helpers/runtime-utils';
import { EContractId } from '../../../helpers/types';
import { deployTask } from '../deploy-steps';

deployTask(`full:deploy-collateral-currency`, `Deploy ${EContractId.CollateralCurrency}`, __dirname).setAction(
  async (_, localBRE) => {
    await localBRE.run('set-DRE');

    const existedCollateralCurrencyAddress = Factories.CollateralCurrency.findInstance(EContractId.CollateralCurrency);

    if (!falsyOrZeroAddress(existedCollateralCurrencyAddress)) {
      console.log(`Already deployed ${EContractId.CollateralCurrency}:`, existedCollateralCurrencyAddress);
      return;
    }

    const accessControllerAddress = Factories.AccessController.findInstance(EContractId.AccessController);

    if (falsyOrZeroAddress(accessControllerAddress)) {
      throw new Error(
        `${EContractId.AccessController} hasn't been deployed yet. Please, deploy ${EContractId.AccessController} first.`
      );
    }

    const deployer = await getFirstSigner();
    const accessController = Factories.AccessController.get(deployer, EContractId.AccessController);
    const collateralCurrency = await Factories.CollateralCurrency.connectAndDeploy(
      deployer,
      EContractId.CollateralCurrency,
      [accessController.address, 'Collateral Currency', 'CC', 18]
    );
    await waitForTx(collateralCurrency.deployTransaction);
  }
);
