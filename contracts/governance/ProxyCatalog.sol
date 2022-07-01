// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';
import '../tools/upgradeability/TransparentProxy.sol';
import '../tools/upgradeability/ProxyAdminBase.sol';
import '../tools/upgradeability/IProxy.sol';
import '../tools/upgradeability/IVersioned.sol';
import '../access/interfaces/IAccessController.sol';
import '../libraries/Strings.sol';
import './interfaces/IProxyCatalog.sol';

contract ProxyCatalog is IManagedProxyCatalog, ProxyAdminBase {
  IAccessController private immutable _remoteAcl;

  mapping(address => address) private _proxies;

  mapping(bytes32 => address) private _defaultImpls;
  mapping(address => bytes32) private _authImpls;
  mapping(address => bytes32) private _revokedImpls;

  constructor(IAccessController remoteAcl) {
    _remoteAcl = remoteAcl;
  }

  function isOwner(address addr) private view returns (bool) {
    IAccessController acl = _remoteAcl;
    return (address(acl) != address(0)) && acl.isAdmin(addr);
  }

  function _onlyOwner() private view {
    Access.require(isOwner(msg.sender));
  }

  modifier onlyOwner() {
    _onlyOwner();
    _;
  }

  function getImplementationType(address impl) public view returns (bytes32 n) {
    n = _authImpls[impl];
    if (n == 0) {
      n = _revokedImpls[impl];
    }
  }

  function isAuthenticImplementation(address impl) public view returns (bool) {
    return _authImpls[impl] != 0;
  }

  function isAuthenticProxy(address proxy) public view returns (bool) {
    return getProxyOwner(proxy) != address(0) && isAuthenticImplementation(getProxyImplementation(proxy));
  }

  function getDefaultImplementation(bytes32 name) public view returns (address addr) {
    State.require((addr = _defaultImpls[name]) != address(0));
    return addr;
  }

  function addAuthenticImplementation(address impl, bytes32 name) public onlyOwner {
    Value.require(name != 0);
    Value.require(impl != address(0));
    bytes32 implName = _authImpls[impl];
    if (implName != name) {
      State.require(implName == 0);
      _authImpls[impl] = name;
      emit ImplementationAdded(name, impl);
    }
  }

  function removeAuthenticImplementation(address impl, address defReplacement) public onlyOwner {
    bytes32 name = _authImpls[impl];
    if (name != 0) {
      delete _authImpls[impl];
      _revokedImpls[impl] = name;
      emit ImplementationRemoved(name, impl);

      if (_defaultImpls[name] == impl) {
        if (defReplacement == address(0)) {
          delete _defaultImpls[name];
          emit DefaultImplementationUpdated(name, address(0));
        } else {
          Value.require(_authImpls[defReplacement] == name);
          _setDefaultImplementation(defReplacement, name, false);
        }
      }
    }
  }

  function unsetDefaultImplementation(address impl) public onlyOwner {
    bytes32 name = _authImpls[impl];
    if (_defaultImpls[name] == impl) {
      delete _defaultImpls[name];
      emit DefaultImplementationUpdated(name, address(0));
    }
  }

  function setDefaultImplementation(address impl) public onlyOwner {
    bytes32 name = _authImpls[impl];
    State.require(name != 0);
    _setDefaultImplementation(impl, name, true);
  }

  function _ensureNewRevision(address prevImpl, address newImpl) internal view {
    require(IVersioned(newImpl).REVISION() > (prevImpl == address(0) ? 0 : IVersioned(prevImpl).REVISION()));
  }

  function _setDefaultImplementation(
    address impl,
    bytes32 name,
    bool checkRevision
  ) private {
    if (checkRevision) {
      _ensureNewRevision(_defaultImpls[name], impl);
    }
    _defaultImpls[name] = impl;
    emit DefaultImplementationUpdated(name, impl);
  }

  function getProxyOwner(address proxy) public view returns (address) {
    return _proxies[proxy];
  }

  /// @dev Returns the current implementation of `proxy`.
  function getProxyImplementation(address proxy) public view returns (address) {
    return _getProxyImplementation(IProxy(proxy));
  }

  function _updateImpl(
    address proxyAddress,
    address newImpl,
    bytes memory params,
    bytes32 name
  ) private {
    TransparentProxy(payable(proxyAddress)).upgradeToAndCall(newImpl, params);
    emit ProxyUpdated(proxyAddress, newImpl, Strings.asString(name), params);
  }

  function _createCustomProxy(
    address adminAddress,
    address implAddress,
    bytes memory params,
    bytes32 name
  ) private returns (TransparentProxy proxy) {
    proxy = new TransparentProxy(adminAddress, implAddress, params);
    emit ProxyCreated(address(proxy), implAddress, Strings.asString(name), params, adminAddress);
  }

  function createCustomProxy(
    address adminAddress,
    address implAddress,
    bytes calldata params
  ) external returns (IProxy) {
    Value.require(adminAddress != address(this));
    return _createCustomProxy(adminAddress, implAddress, params, '');
  }

  function _createProxy(
    address adminAddress,
    address implAddress,
    bytes memory params,
    bytes32 name
  ) private returns (TransparentProxy) {
    TransparentProxy proxy = _createCustomProxy(address(this), implAddress, params, name);
    _proxies[address(proxy)] = adminAddress == address(0) ? address(this) : adminAddress;
    return proxy;
  }

  function createProxy(
    address adminAddress,
    bytes32 implName,
    bytes memory params
  ) external returns (address) {
    // TODO access ???
    return address(_createProxy(adminAddress, getDefaultImplementation(implName), params, implName));
  }

  function createProxyWithImpl(
    address adminAddress,
    address impl,
    bytes calldata params
  ) external onlyOwner returns (address) {
    bytes32 name = _authImpls[impl];
    State.require(name != 0);
    return address(_createProxy(adminAddress, impl, params, name));
  }

  function _onlyOwnerOrProxyAdmin(address proxyAddress) private view {
    Access.require(getProxyOwner(proxyAddress) == msg.sender || isOwner(msg.sender));
  }

  modifier onlyOwnerOrProxyAdmin(address proxyAddress) {
    _onlyOwnerOrProxyAdmin(proxyAddress);
    _;
  }

  function upgradeProxy(address proxyAddress, bytes calldata params) external onlyOwnerOrProxyAdmin(proxyAddress) returns (bool) {
    address prevImpl = getProxyImplementation(proxyAddress);
    bytes32 name = getImplementationType(prevImpl);
    address newImpl = getDefaultImplementation(name);
    if (prevImpl != newImpl) {
      _ensureNewRevision(prevImpl, newImpl);
      _updateImpl(proxyAddress, newImpl, params, name);
      return true;
    }
    return false;
  }

  function upgradeProxyWithImpl(
    address proxyAddress,
    address newImpl,
    bool checkRevision,
    bytes calldata params
  ) external onlyOwner returns (bool) {
    address prevImpl = getProxyImplementation(proxyAddress);
    if (prevImpl != newImpl) {
      bytes32 name = getImplementationType(prevImpl);
      bytes32 name2 = getImplementationType(newImpl);
      if (name != 0 || checkRevision) {
        Value.require(name == name2 || name == 0 || (!checkRevision && name2 == 0));
      }

      if (checkRevision) {
        _ensureNewRevision(prevImpl, newImpl);
      }

      _updateImpl(proxyAddress, newImpl, params, name2);
      return true;
    }
    return false;
  }
}
