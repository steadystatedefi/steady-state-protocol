import { zeroAddress } from 'ethereumjs-util';

import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { WeightedPoolParamsStruct } from '../../../types/contracts/insurer/ImperpetualPoolBase';
import { deployTask } from '../deploy-steps';

import { deployProxyFromCatalog } from './templates';

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

    const initFunctionData = factory
      .attach(zeroAddress())
      .interface.encodeFunctionData('initializeWeighted', [governor, 'Indexed Pool Token', 'IPT', poolParams]);

    await deployProxyFromCatalog(catalogName, initFunctionData);

    // TODO register with the premium fund -
    // ip.setPremiumDistributor
    // pf.registerPremiumActuary
    // TODO register with collateral currency
  })
);
