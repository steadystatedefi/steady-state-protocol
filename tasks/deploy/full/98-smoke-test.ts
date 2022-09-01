import { task } from 'hardhat/config';

import { AccessFlags } from '../../../helpers/access-flags';
import { ConfigNamesAsString } from '../../../helpers/config-loader';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';

task(`full:smoke-test`, 'Smoke test')
  .addOptionalParam('cfg', `Configuration name: ${ConfigNamesAsString}`)
  .setAction(
    dreAction(async () => {
      const ac = Factories.AccessController.get();
      const dh = Factories.FrontHelper.attach(await ac.getAddress(AccessFlags.DATA_HELPER));

      const config = await dh.getAddresses();
      const po = Factories.OracleRouterV1.attach(config.priceRouter);
      if (config.collateralFunds.length === 0) {
        throw new Error(`Found no collateral funds`);
      }
      console.log(`Found ${config.collateralFunds.length} collateral fund(s)`);
      console.log(`Found ${config.insurers.length} insurer(s)`);

      if (config.collateralFunds.length === 0) {
        throw new Error(`Found no collateral funds`);
      }
      if (config.insurers.length === 0) {
        throw new Error(`Found no insurers`);
      }

      const poAddr = po.address.toUpperCase();

      for (const fundInfo of config.collateralFunds) {
        if (fundInfo.assets.length === 0) {
          throw new Error(`Collateral fund ${fundInfo.fund} has no assets`);
        }
        console.log(`Collateral fund ${fundInfo.fund} has ${fundInfo.assets.length} asset(s). Checking prices ...`);

        const fund = Factories.CollateralFundV1.attach(fundInfo.fund);
        {
          const addr = await fund.priceOracle();
          if (poAddr !== addr.toUpperCase()) {
            throw new Error(
              `Collateral fund ${fundInfo.fund} has a different price oracle: ${addr} instead of ${po.address}`
            );
          }
        }

        let hasError = true;
        try {
          const foundPrices = await po.getAssetPrices(fundInfo.assets);
          hasError = false;
          foundPrices.forEach((price, index) => {
            if (price.eq(0)) {
              throw new Error(`Invalid (zero) price for ${fundInfo.assets[index]}`);
            }
          });
        } catch (err: unknown) {
          if (!hasError) {
            console.log(`Invalid price detected. Checking sources individualy...`);
            await Promise.all(
              fundInfo.assets.map(async (addr) => {
                try {
                  const price = await po.getAssetPrice(addr);
                  if (!price.eq(0)) {
                    return;
                  }
                  // eslint-disable-next-line no-empty
                } catch {}
                console.log(`Price source has failed for ${addr}`);
              })
            );
          }
          throw err;
        }
      }
    })
  );
