import { zeroAddress } from 'ethereumjs-util';
import { BigNumber, Contract } from 'ethers';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import {
  addNamedToJsonDb,
  addProxyToJsonDb,
  getAddrFromJsonDb,
  getExternalsFromJsonDb,
  isExternalNeedsSync,
  setExternalNeedsSync,
} from '../../helpers/deploy-db';
import { NamedAttachable } from '../../helpers/factory-wrapper';
import {
  ensureValidAddress,
  falsyOrZeroAddress,
  notFalsyOrZeroAddress,
  sleep,
  waitForTx,
} from '../../helpers/runtime-utils';
import { AccessController } from '../../types';

export const findDeployedProxy = (name: string): string => getAddrFromJsonDb(name);
export const getDeployedProxy = (name: string): string => ensureValidAddress(findDeployedProxy(name), name);

export const getSyncedDeployedProxy = async (name: string, maxWait?: number): Promise<string> => {
  const addr = ensureValidAddress(findDeployedProxy(name), name);
  await waitForProxy(addr, maxWait);
  return addr;
};

export const findCatalogDeployedProxy = (catalogBaseName: string, subInstance?: string): string => {
  const catalogName = subInstance ? `${catalogBaseName}-${subInstance}` : catalogBaseName;
  const addr = getAddrFromJsonDb(catalogName);
  return addr;
};

export async function deployProxyFromCatalog(
  factory: NamedAttachable,
  catalogBaseName: string,
  initFunctionData: string,
  subInstance?: string,
  ctx?: string
): Promise<string> {
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
  setExternalNeedsSync(contractAddr, true);
  addNamedToJsonDb(catalogName, contractAddr);

  return contractAddr;
}

export async function findOrDeployProxyFromCatalog<C extends Contract>(
  factory: NamedAttachable<C>,
  catalogBaseName: string,
  initFunctionData: string,
  subInstance?: string,
  ctx?: string
): Promise<[C, boolean]> {
  let addr = findCatalogDeployedProxy(catalogBaseName, subInstance);
  let newDeploy = false;
  if (falsyOrZeroAddress(addr)) {
    addr = await deployProxyFromCatalog(factory, catalogBaseName, initFunctionData, subInstance, ctx);
    newDeploy = true;
  }
  return [factory.attach(addr), newDeploy];
}

export async function assignRole(
  accessFlag: BigNumber | number,
  addr: string,
  newDeploy?: boolean,
  ac?: AccessController
): Promise<void> {
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
}

export async function waitForProxy(address: string, maxWait?: number | null, silent?: boolean): Promise<boolean> {
  if (!isExternalNeedsSync(address)) {
    return true;
  }
  const proxyCatalog = Factories.ProxyCatalog.get();

  const minPeriod = 5;
  const maxPeriod = 60;
  for (let i = 0; i < (maxWait ?? Number.MAX_SAFE_INTEGER); ) {
    // a periodic sanity check that the proxy is in the catalog and the catalog is operations
    if (falsyOrZeroAddress(await proxyCatalog.getProxyOwner(address))) {
      if (silent) {
        return false;
      }
      throw new Error(`Can only wait for proxies from the catalog: ${address}`);
    }

    let implAddr = '';
    try {
      implAddr = await proxyCatalog.getProxyImplementation(address);
    } catch {
      // can safely ignore any exceptions as the catalog is working and proxy address is known to it
    }
    if (notFalsyOrZeroAddress(implAddr)) {
      setExternalNeedsSync(address, false);
      return true;
    }

    const d = i < minPeriod * 2 ? minPeriod : minPeriod * Math.trunc(i / minPeriod);
    const period = d < maxPeriod ? d : minPeriod;
    i += period;

    await sleep(period * 1000);
  }
  return false;
}

export async function syncAllDeployedProxies(): Promise<void> {
  const entries = getExternalsFromJsonDb();

  // NB! There is NO need to do it in parallel, as will only hammer a provider with multiple requests
  for (const [addr, entry] of entries) {
    if (entry.needsSync) {
      console.log('\tSync for', entry.id, '@', addr);
      if (!(await waitForProxy(addr, null, true))) {
        console.log(`\t\tnot sync'ed`);
      }
    }
  }
}
