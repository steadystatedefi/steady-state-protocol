import { zeroAddress } from 'ethereumjs-util';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { addNamedToJsonDb, addProxyToJsonDb, getAddrFromJsonDb } from '../../../helpers/deploy-db';
import { ensureValidAddress, notFalsyOrZeroAddress } from '../../../helpers/runtime-utils';

export const findDeployedProxy = (name: string): string => getAddrFromJsonDb(name);
export const getDeployedProxy = (name: string): string => ensureValidAddress(findDeployedProxy(name), name);

export const deployProxyFromCatalog = async (
  catalogBaseName: string,
  initFunctionData: string,
  subInstance?: string,
  ctx?: string
): Promise<string> => {
  const proxyCatalog = Factories.ProxyCatalog.get();
  const catalogType = formatBytes32String(catalogBaseName);

  const catalogName = subInstance ? `${catalogBaseName}-${subInstance}` : catalogBaseName;
  const found = findDeployedProxy(catalogName);
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
  addNamedToJsonDb(catalogName, contractAddr);

  return contractAddr;
};
