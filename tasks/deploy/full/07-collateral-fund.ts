import { zeroAddress } from 'ethereumjs-util';

import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog } from './templates';

const catalogName = ProxyTypes.COLLATERAL_FUND;

deployTask(`full:deploy-collateral-fund`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const factory = Factories.CollateralFundV1;
    const cc = Factories.CollateralCurrency.get();
    const initFunctionData = factory.attach(zeroAddress()).interface.encodeFunctionData('initializeCollateralFund');

    const collateralFundAddr = await deployProxyFromCatalog(catalogName, initFunctionData);

    if (!(await cc.isLiquidityProvider(collateralFundAddr))) {
      await mustWaitTx(cc.registerLiquidityProvider(collateralFundAddr));
    }

    // const collateralFund = factory.attach(collateralFundAddr);
    // TODO collateralFund.addAsset()
  })
);
