import { zeroAddress } from 'ethereumjs-util';

import { AccessFlags } from '../../../helpers/access-flags';
import { Factories } from '../../../helpers/contract-types';
import { dreAction } from '../../../helpers/dre';
import { ProxyTypes } from '../../../helpers/proxy-types';
import { deployTask } from '../deploy-steps';
import { assignRole, findOrDeployProxyFromCatalog } from '../templates';

const catalogName = ProxyTypes.APPROVAL_CATALOG;

deployTask(`full:deploy-approval-catalog`, `Deploy ${catalogName}`, __dirname).setAction(
  dreAction(async () => {
    const factory = Factories.ApprovalCatalogV1;

    const initFunctionData = factory.interface.encodeFunctionData('initializeApprovalCatalog');
    const [catalog, newDeploy] = await findOrDeployProxyFromCatalog(
      factory,
      catalogName,
      initFunctionData,
      '',
      zeroAddress()
    );

    await assignRole(AccessFlags.APPROVAL_CATALOG, catalog.address, newDeploy);
  })
);
