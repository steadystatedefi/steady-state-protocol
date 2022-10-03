import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { BytesLike, formatBytes32String } from 'ethers/lib/utils';

import { AccessFlags } from '../../../helpers/access-flags';
import { Events } from '../../../helpers/contract-events';
import { Factories } from '../../../helpers/contract-types';
import { MockVersionedInitializable1, MockVersionedInitializable2 } from '../../../types';
import { makeSuite, TestEnv } from '../setup/make-suite';

import { deployAccessControlState, State } from './setup';

makeSuite('access: Proxy Catalog', (testEnv: TestEnv) => {
  let deployer: SignerWithAddress;
  let state: State;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  const implName = formatBytes32String('AccessTestImpl');
  let ctx: string;

  let version1: MockVersionedInitializable1;
  let version2: MockVersionedInitializable2;
  let params: string;

  before(async () => {
    deployer = testEnv.deployer;
    user2 = testEnv.users[2];
    user3 = testEnv.users[3];
    state = await deployAccessControlState(deployer);

    version1 = await Factories.MockVersionedInitializable1.deploy();
    version2 = await Factories.MockVersionedInitializable2.deploy();
    ctx = state.cc.address;
    params = version1.interface.encodeFunctionData('initialize', ['test']);
  });

  async function makeProxy(owner: string, par: BytesLike): Promise<string> {
    let proxyAddr = '';
    await Events.ProxyCreated.waitOne(state.proxyCatalog.createProxy(user3.address, implName, ctx, par), (ev) => {
      proxyAddr = ev.proxy;
    });
    return proxyAddr;
  }

  it('ROLE: Admin', async () => {
    const user2proxy = state.proxyCatalog.connect(user2);
    {
      await expect(user2proxy.addAuthenticImplementation(version1.address, implName, ctx)).reverted;
      await expect(user2proxy.removeAuthenticImplementation(version1.address, zeroAddress())).reverted;
    }
    {
      await state.proxyCatalog.addAuthenticImplementation(version1.address, implName, ctx);
      await state.proxyCatalog.removeAuthenticImplementation(version1.address, zeroAddress());
      await state.proxyCatalog.addAuthenticImplementation(version1.address, implName, ctx);
    }
    {
      await expect(user2proxy.setDefaultImplementation(version1.address)).reverted;
      await expect(user2proxy.unsetDefaultImplementation(version1.address)).reverted;
    }
    {
      await state.proxyCatalog.setDefaultImplementation(version1.address);
      await state.proxyCatalog.unsetDefaultImplementation(version1.address);
      await state.proxyCatalog.setDefaultImplementation(version1.address);
    }

    const proxy = await makeProxy(user3.address, params);
    const proxy2 = await makeProxy(user3.address, params);

    await state.proxyCatalog.addAuthenticImplementation(version2.address, implName, ctx);
    await state.proxyCatalog.setDefaultImplementation(version2.address);
    {
      await expect(user2proxy.upgradeProxy(proxy, params)).reverted;
      await expect(user2proxy.upgradeProxyWithImpl(proxy2, version2.address, true, params)).reverted;
      await expect(state.proxyCatalog.connect(user3).upgradeProxyWithImpl(proxy2, version2.address, true, params))
        .reverted;
    }

    await state.proxyCatalog.upgradeProxy(proxy, params);
    await state.proxyCatalog.upgradeProxyWithImpl(proxy2, version2.address, true, params);
  });

  it('ROLE: Implementation Access', async () => {
    await state.proxyCatalog.addAuthenticImplementation(version1.address, implName, ctx);
    await state.proxyCatalog.setDefaultImplementation(version1.address);
    await state.proxyCatalog.addAuthenticImplementation(version2.address, implName, ctx);
    const validFlag = AccessFlags.LIQUIDITY_MANAGER;

    await expect(state.proxyCatalog.connect(user3).setAccess([implName], [validFlag])).reverted;
    await state.proxyCatalog.setAccess([implName], [validFlag]);
    {
      await expect(makeProxy(user3.address, params)).reverted;
      await expect(state.proxyCatalog.createProxyWithImpl(user3.address, implName, version2.address, params)).reverted;
    }

    await state.controller.grantRoles(deployer.address, validFlag);
    {
      expect(await makeProxy(user3.address, params)).not.eq('');
      await state.proxyCatalog.createProxyWithImpl(user3.address, implName, version2.address, params);
    }
  });

  it('ROLE: Proxy Owner', async () => {
    await state.proxyCatalog.addAuthenticImplementation(version1.address, implName, ctx);
    await state.proxyCatalog.setDefaultImplementation(version1.address);
    await state.proxyCatalog.addAuthenticImplementation(version2.address, implName, ctx);

    const proxy = await makeProxy(user3.address, params);
    //    const proxy2 = await makeProxy(user3.address, params);

    await state.proxyCatalog.connect(user3).upgradeProxy(proxy, params);
  });
});
