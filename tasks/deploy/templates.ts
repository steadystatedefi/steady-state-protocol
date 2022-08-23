import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, Contract } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import { addNamedToJsonDb, addProxyToJsonDb, getAddrFromJsonDb } from '../../helpers/deploy-db';
import { NamedAttachable } from '../../helpers/factory-wrapper';
import { ensureValidAddress, falsyOrZeroAddress, notFalsyOrZeroAddress, waitForTx } from '../../helpers/runtime-utils';
import { AccessController } from '../../types';

export const findDeployedProxy = (name: string): string => getAddrFromJsonDb(name);
export const getDeployedProxy = (name: string): string => ensureValidAddress(findDeployedProxy(name), name);

export const findCatalogDeployedProxy = (catalogBaseName: string, subInstance?: string): string => {
  const catalogName = subInstance ? `${catalogBaseName}-${subInstance}` : catalogBaseName;
  return getAddrFromJsonDb(catalogName);
};

export const deployProxyFromCatalog = async (
  factory: NamedAttachable,
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

  addProxyToJsonDb(catalogName, contractAddr, contractImpl, subInstance ?? '', factory.name() ?? '', [
    proxyCatalog.address,
    contractImpl,
    initFunctionData,
  ]);
  addNamedToJsonDb(catalogName, contractAddr);

  return contractAddr;
};

export const findOrDeployProxyFromCatalog = async <C extends Contract>(
  factory: NamedAttachable<C>,
  catalogBaseName: string,
  initFunctionData: string,
  subInstance?: string,
  ctx?: string
): Promise<[C, boolean]> => {
  let addr = findCatalogDeployedProxy(catalogBaseName, subInstance);
  let newDeploy = false;
  if (falsyOrZeroAddress(addr)) {
    addr = await deployProxyFromCatalog(factory, catalogBaseName, initFunctionData, subInstance, ctx);
    newDeploy = true;
  }
  return [factory.attach(addr), newDeploy];
};

export const assignRole = async (
  accessFlag: BigNumber | number,
  addr: string,
  newDeploy?: boolean,
  ac?: AccessController
): Promise<void> => {
  const accessController = ac || Factories.AccessController.get();
  const found = newDeploy ? '' : await accessController.getAddress(accessFlag);
  if (notFalsyOrZeroAddress(found)) {
    console.log(`Already deployed: ${found}`);
    if (found.toUpperCase() !== addr.toUpperCase()) {
      throw new Error(`Deployed address mismatched: ${found} ${addr}`);
    }
  } else {
    await waitForTx(await accessController.setAddress(accessFlag, addr));
  }
};
