import { loadNetworkConfig } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { deployTask } from '../deploy-steps';

deployTask(`dev:pre-deploy`, `Deploy dependency mocks`, __dirname).setAction(
  dreAction(async ({ cfg: configName }) => {
    const cfg = loadNetworkConfig(configName as string);

    for (const [assetName] of Object.entries(cfg.Assets)) {
      const decimals = cfg.PriceFeeds[assetName]?.decimals;

      if (!decimals) {
        throw new Error(`config must contain decimals for asset ${assetName}`);
      }

      const m = await Factories.MockERC20.deploy(assetName, assetName, decimals);
      console.log('Deployed ERC20 mock:', assetName, m.address);
      cfg.Assets[assetName] = m.address;
    }
  })
);
