import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { zeroAddress } from 'ethereumjs-util';
import { formatBytes32String } from 'ethers/lib/utils';

import { Events } from '../../helpers/contract-events';
import { Factories } from '../../helpers/contract-types';
import { AccessController, MockVersionedInitializable1, MockVersionedInitializable2, ProxyCatalog } from '../../types';

import { makeSuite, TestEnv } from './setup/make-suite';

const ZERO_BYTES = formatBytes32String('');

const implStr = 'MockToken';
const implName = formatBytes32String(implStr);

makeSuite('Proxy Catalog', (testEnv: TestEnv) => {
  let controller: AccessController;
  let proxyCatalog: ProxyCatalog;
  let rev1: MockVersionedInitializable1;
  let rev2: MockVersionedInitializable2;
  let user1: SignerWithAddress;

  const proxyUpgradeTest = async (useUser1: boolean) => {
    let proxyAddr = '';
    let name = 'test name 1';
    const admin = useUser1 ? user1.address : zeroAddress();

    await proxyCatalog.addAuthenticImplementation(rev1.address, implName);
    await proxyCatalog.addAuthenticImplementation(rev2.address, implName);

    await proxyCatalog.setDefaultImplementation(rev1.address);
    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxy(admin, implName, rev1.interface.encodeFunctionData('initialize', [name])),
      (ev) => {
        proxyAddr = ev.proxy;
        expect(ev.impl).eq(rev1.address);
        expect(ev.typ).eq(implStr);
        expect(ev.admin).eq(proxyCatalog.address);
      }
    );

    const contract = Factories.MockVersionedInitializable1.attach(proxyAddr);
    expect(await contract.REVISION()).eq(await rev1.REVISION());
    expect(await contract.name()).eq(name);
    expect(await proxyCatalog.getProxyImplementation(proxyAddr)).eq(rev1.address);
    expect(await proxyCatalog.isAuthenticProxy(proxyAddr)).eq(true);

    name = 'test name 2';
    const res = await proxyCatalog.callStatic.upgradeProxy(
      proxyAddr,
      rev1.interface.encodeFunctionData('initialize', [name])
    );
    expect(res).eq(false);

    await proxyCatalog.setDefaultImplementation(rev2.address);
    const upgrade = proxyCatalog
      .connect(user1)
      .upgradeProxy(proxyAddr, rev2.interface.encodeFunctionData('initialize', [name]));
    if (useUser1) {
      await upgrade;
    } else {
      await expect(upgrade).to.be.reverted;
      await proxyCatalog.upgradeProxy(proxyAddr, rev2.interface.encodeFunctionData('initialize', [name]));
    }

    expect(await contract.REVISION()).eq(await rev2.REVISION());
    expect(await contract.name()).eq(name);
    expect(await proxyCatalog.getProxyImplementation(proxyAddr)).eq(rev2.address);
  };

  before(async () => {
    user1 = testEnv.users[1];
    controller = await Factories.AccessController.deploy(0);
    proxyCatalog = await Factories.ProxyCatalog.deploy(controller.address);
    rev1 = await Factories.MockVersionedInitializable1.deploy();
    rev2 = await Factories.MockVersionedInitializable2.deploy();
  });

  it('Authentic implementation', async () => {
    await expect(proxyCatalog.addAuthenticImplementation(zeroAddress(), implName)).to.be.reverted;
    await expect(proxyCatalog.addAuthenticImplementation(rev1.address, '')).to.be.reverted;
    expect(await proxyCatalog.isAuthenticImplementation(rev1.address)).eq(false);
    expect(await proxyCatalog.getImplementationType(rev1.address)).eq(ZERO_BYTES);

    await proxyCatalog.addAuthenticImplementation(rev1.address, implName);
    {
      expect(await proxyCatalog.isAuthenticImplementation(rev1.address)).eq(true);
      expect(await proxyCatalog.getImplementationType(rev1.address)).eq(implName);
    }

    await proxyCatalog.removeAuthenticImplementation(rev1.address, zeroAddress());
    {
      expect(await proxyCatalog.isAuthenticImplementation(rev1.address)).eq(false);
      expect(await proxyCatalog.getImplementationType(rev1.address)).eq(implName);
    }
  });

  it('Default implementation', async () => {
    const rev1dup = await Factories.MockVersionedInitializable1.deploy();
    const rev3 = await Factories.MockVersionedInitializable2.deploy();

    await proxyCatalog.addAuthenticImplementation(rev1.address, implName);
    await proxyCatalog.addAuthenticImplementation(rev2.address, implName);
    await proxyCatalog.addAuthenticImplementation(rev1dup.address, implName);
    await expect(proxyCatalog.getDefaultImplementation(implName)).to.be.reverted;

    await proxyCatalog.setDefaultImplementation(rev1.address);
    expect(await proxyCatalog.getDefaultImplementation(implName)).eq(rev1.address);
    await expect(proxyCatalog.setDefaultImplementation(rev1dup.address)).to.be.reverted;

    await proxyCatalog.setDefaultImplementation(rev2.address);
    expect(await proxyCatalog.getDefaultImplementation(implName)).eq(rev2.address);

    await proxyCatalog.removeAuthenticImplementation(rev1dup.address, zeroAddress());
    await proxyCatalog.removeAuthenticImplementation(rev2.address, rev1.address);
    await expect(proxyCatalog.removeAuthenticImplementation(rev1.address, rev3.address)).to.be.reverted;
    await proxyCatalog.addAuthenticImplementation(rev3.address, implName);
    await proxyCatalog.removeAuthenticImplementation(rev1.address, rev3.address);
    expect(await proxyCatalog.getDefaultImplementation(implName)).eq(rev3.address);

    await proxyCatalog.unsetDefaultImplementation(rev3.address);
    await expect(proxyCatalog.getDefaultImplementation(implName)).to.be.reverted;
    await proxyCatalog.setDefaultImplementation(rev3.address);
    await proxyCatalog.removeAuthenticImplementation(rev3.address, zeroAddress());
  });

  it('Create and upgrade catalog-owned proxy', async () => {
    await proxyUpgradeTest(false);
  });

  it('Create and upgrade user-owned proxy', async () => {
    await proxyUpgradeTest(true);
  });

  it('Upgrade proxy directly with implementation', async () => {
    let proxyAddr = '';
    let name = 'test name 1';

    await proxyCatalog.addAuthenticImplementation(rev1.address, implName);
    await proxyCatalog.addAuthenticImplementation(rev2.address, implName);

    await proxyCatalog.setDefaultImplementation(rev1.address);
    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxy(zeroAddress(), implName, rev1.interface.encodeFunctionData('initialize', [name])),
      (ev) => {
        proxyAddr = ev.proxy;
        expect(ev.impl).eq(rev1.address);
      }
    );
    const contract = Factories.MockVersionedInitializable1.attach(proxyAddr);
    expect(
      await proxyCatalog.callStatic.upgradeProxyWithImpl(
        proxyAddr,
        rev1.address,
        true,
        rev1.interface.encodeFunctionData('initialize', [name])
      )
    ).eq(false);

    name = 'test name 2';
    await proxyCatalog.upgradeProxyWithImpl(
      proxyAddr,
      rev2.address,
      true,
      rev2.interface.encodeFunctionData('initialize', [name])
    );
    expect(await contract.REVISION()).eq(await rev2.REVISION());
    expect(await contract.name()).eq(name);
    expect(await proxyCatalog.getProxyImplementation(proxyAddr)).eq(rev2.address);

    await proxyCatalog.upgradeProxyWithImpl(proxyAddr, rev1.address, false, rev1.interface.encodeFunctionData('name'));
    expect(await contract.REVISION()).eq(await rev1.REVISION());
    expect(await contract.name()).eq(name);
    expect(await proxyCatalog.getProxyImplementation(proxyAddr)).eq(rev1.address);
  });

  it('Create proxy with implementation', async () => {
    let proxyAddr = '';
    const name = 'test name 1';
    const params = rev2.interface.encodeFunctionData('initialize', [name]);

    await proxyCatalog.addAuthenticImplementation(rev1.address, implName);
    await proxyCatalog.setDefaultImplementation(rev1.address);

    await expect(proxyCatalog.createProxyWithImpl(user1.address, formatBytes32String(''), rev1.address, params)).to.be
      .reverted;
    await expect(proxyCatalog.createProxyWithImpl(user1.address, implName, rev2.address, params)).to.be.reverted;

    await proxyCatalog.addAuthenticImplementation(rev2.address, implName);
    await Events.ProxyCreated.waitOne(
      proxyCatalog.createProxyWithImpl(user1.address, implName, rev2.address, params),
      (ev) => {
        proxyAddr = ev.proxy;
        expect(ev.impl).eq(rev2.address);
      }
    );

    const contract = Factories.MockVersionedInitializable1.attach(proxyAddr);
    expect(await contract.REVISION()).eq(await rev2.REVISION());
    expect(await contract.name()).eq(name);
    expect(await proxyCatalog.getProxyImplementation(proxyAddr)).eq(rev2.address);
  });

  it('Create custom proxy', async () => {
    let proxyAddr = '';
    const name = 'test name 2';
    const params = rev2.interface.encodeFunctionData('initialize', [name]);
    await expect(proxyCatalog.createCustomProxy(proxyCatalog.address, rev2.address, params)).to.be.reverted;

    expect(await proxyCatalog.isAuthenticImplementation(rev2.address)).eq(false);
    await Events.ProxyCreated.waitOne(proxyCatalog.createCustomProxy(user1.address, rev2.address, params), (ev) => {
      proxyAddr = ev.proxy;
      expect(ev.impl).eq(rev2.address);
    });

    const contract = Factories.MockVersionedInitializable2.attach(proxyAddr);
    const proxyContract = Factories.TransparentProxy.attach(proxyAddr);
    expect(await contract.REVISION()).eq(await rev2.REVISION());
    expect(await contract.name()).eq(name);
    expect(await proxyCatalog.isAuthenticProxy(proxyAddr)).eq(false);

    await expect(proxyCatalog.getProxyImplementation(proxyAddr)).to.be.reverted;
    expect(await proxyContract.connect(user1).callStatic.implementation()).eq(rev2.address);
  });
});
