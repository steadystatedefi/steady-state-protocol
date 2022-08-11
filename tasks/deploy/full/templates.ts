import { zeroAddress } from 'ethereumjs-util';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addProxyToJsonDb, getAddrFromJsonDb } from '../../../helpers/deploy-db';
import { notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';

export const deployProxyFromCatalog = async (
  catalogName: string,
  initFunctionData: string,
  subInstance?: string,
  ctx?: string
): Promise<string> => {
  const proxyCatalog = Factories.ProxyCatalog.get();
  const catalogType = formatBytes32String(catalogName);

  const found = getAddrFromJsonDb(catalogName);
  if (notFalsyOrZeroAddress(found)) {
    console.log(`Already deployed: ${found}`);
    return found;
  }

  let contractAddr = '';
  let contractImpl = '';
  await Events.ProxyCreated.waitOne(
    proxyCatalog.createProxy(
      zeroAddress(),
      catalogType,
      ctx ?? Factories.CollateralCurrency.get().address,
      initFunctionData
    ),
    (event) => {
      contractAddr = event.proxy;
      contractImpl = event.impl;
    }
  );

  console.log(`${catalogName}: ${contractAddr} => ${contractImpl}`);

  addProxyToJsonDb(catalogName, contractAddr, contractImpl, subInstance ?? '', [
    proxyCatalog.address,
    contractImpl,
    initFunctionData,
  ]);

  return contractAddr;
};
