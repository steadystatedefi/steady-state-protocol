import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { deployTask } from '../deploy-steps';

deployTask(`dev:pre-deploy`, `Deploy dependency mocks`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    for (const [assetName] of Object.entries(cfg.Assets)) {
      const m = await Factories.MockERC20.deploy(assetName, assetName, 6);
      console.log('Deployed ERC20 mock:', assetName, m.address);
      cfg.Assets[assetName] = m.address;
    }
  })
);
