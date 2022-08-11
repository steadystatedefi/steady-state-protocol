import { zeroAddress } from 'ethereumjs-util';

import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { mustWaitTx } from '../../../helpers/runtime-utils';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog, getDeployedProxy } from './templates';

const catalogName = ProxyTypes.IMPERPETUAL_INDEX_POOL;

deployTask(`full:deploy-index-pool`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const factory = Factories.ImperpetualPoolV1;

    const poolParams: WeightedPoolParamsStruct = {
      maxAdvanceUnits: 10000,
      minAdvanceUnits: 1000,
      riskWeightTarget: 1000, // 10%
      minInsuredSharePct: 100, // 1%
      maxInsuredSharePct: 4000, // 40%
      minUnitsPerRound: 20,
      maxUnitsPerRound: 20,
      overUnitsPerRound: 30,
      coveragePrepayPct: 9000, // 90%
      maxUserDrawdownPct: 1000, // 10%
      unitsPerAutoPull: 0,
    };
    const governor = zeroAddress();

    const initFunctionData = factory.interface.encodeFunctionData('initializeWeighted', [
      governor,
      'Indexed Pool Token',
      'IPT',
      poolParams,
    ]);

    const poolAddr = await deployProxyFromCatalog(catalogName, initFunctionData);
    const pool = factory.attach(poolAddr);

    const pfFactory = Factories.PremiumFundV1;
    const pf = pfFactory.attach(getDeployedProxy(ProxyTypes.PREMIUM_FUND));
    const cc = Factories.CollateralCurrency.get();

    await mustWaitTx(pool.setPremiumDistributor(pf.address));
    await mustWaitTx(pf.registerPremiumActuary(pool.address, true));
    await mustWaitTx(cc.registerInsurer(pool.address));
  })
);
