// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';
import '../tools/upgradeability/TransparentProxy.sol';
import '../tools/upgradeability/ProxyAdminBase.sol';
import '../tools/upgradeability/IProxy.sol';
import '../tools/upgradeability/IVersioned.sol';
import '../access/interfaces/IAccessController.sol';
import '../access/AccessHelper.sol';
import '../libraries/Strings.sol';
import './interfaces/IProxyCatalog.sol';

contract ProxyCatalog is IManagedProxyCatalog, ProxyAdminBase, AccessHelper {
  mapping(address => address) private _proxyOwners; // [proxy]

  mapping(address => mapping(bytes32 => address)) private _defaultImpls; // [ctx][name]
  mapping(address => bytes32) private _authImpls; // [impl]
  mapping(address => bytes32) private _revokedImpls; // [impl]
  mapping(address => address) private _contexts; // [impl]
  mapping(bytes32 => uint256) private _accessRoles;

  constructor(IAccessController acl) AccessHelper(acl) {}

  function getImplementationType(address impl) public view override returns (bytes32 name, address ctx) {
    name = _authImpls[impl];
    if (name == 0) {
      name = _revokedImpls[impl];
    }
    ctx = _contexts[impl];
  }

  function isAuthenticImplementation(address impl) public view override returns (bool) {
    return impl != address(0) && _authImpls[impl] != 0;
  }

  function isAuthenticProxy(address proxy) public view override returns (bool) {
    return getProxyOwner(proxy) != address(0) && isAuthenticImplementation(getProxyImplementation(proxy));
  }

  function getDefaultImplementation(bytes32 name, address ctx) public view override returns (address addr) {
    State.require((addr = _defaultImpls[ctx][name]) != address(0));
  }

  function addAuthenticImplementation(
    address impl,
    bytes32 name,
    address ctx
  ) public onlyAdmin {
    Value.require(name != 0);
    Value.require(impl != address(0));
    bytes32 implName = _authImpls[impl];
    if (implName != name) {
      State.require(implName == 0);
      _authImpls[impl] = name;
      _contexts[impl] = ctx;
      emit ImplementationAdded(name, ctx, impl);
    } else {
      State.require(ctx == _contexts[impl]);
    }
  }

  function removeAuthenticImplementation(address impl, address defReplacement) public onlyAdmin {
    bytes32 name = _authImpls[impl];
    if (name != 0) {
      delete _authImpls[impl];
      _revokedImpls[impl] = name;
      address ctx = _contexts[impl];
      emit ImplementationRemoved(name, ctx, impl);

      if (_defaultImpls[ctx][name] == impl) {
        if (defReplacement == address(0)) {
          delete _defaultImpls[ctx][name];
          emit DefaultImplementationUpdated(name, ctx, address(0));
        } else {
          Value.require(_authImpls[defReplacement] == name && _contexts[defReplacement] == ctx);
          _setDefaultImplementation(defReplacement, name, ctx, false);
        }
      }
    }
  }

  function unsetDefaultImplementation(address impl) public onlyAdmin {
    bytes32 name = _authImpls[impl];
    address ctx = _contexts[impl];
    if (_defaultImpls[ctx][name] == impl) {
      delete _defaultImpls[ctx][name];
      emit DefaultImplementationUpdated(name, ctx, address(0));
    }
  }

  function setDefaultImplementation(address impl) public onlyAdmin {
    bytes32 name = _authImpls[impl];
    State.require(name != 0);
    _setDefaultImplementation(impl, name, _contexts[impl], true);
  }

  function _ensureNewRevision(address prevImpl, address newImpl) internal view {
    Value.require(IVersioned(newImpl).REVISION() > (prevImpl == address(0) ? 0 : IVersioned(prevImpl).REVISION()));
  }

  function _setDefaultImplementation(
    address impl,
    bytes32 name,
    address ctx,
    bool checkRevision
  ) private {
    if (checkRevision) {
      _ensureNewRevision(_defaultImpls[ctx][name], impl);
    }
    _defaultImpls[ctx][name] = impl;
    emit DefaultImplementationUpdated(name, ctx, impl);
  }

  function getProxyOwner(address proxy) public view returns (address) {
    return _proxyOwners[proxy];
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
    _proxyOwners[address(proxy)] = adminAddress == address(0) ? address(this) : adminAddress;
    return proxy;
  }

  function getAccess(bytes32[] calldata implNames) external view returns (uint256[] memory results) {
    results = new uint256[](implNames.length);
    for (uint256 i = implNames.length; i > 0; ) {
      i--;
      results[i] = _accessRoles[implNames[i]];
    }
  }

  function setAccess(bytes32[] calldata implNames, uint256[] calldata accessFlags) external onlyAdmin {
    Value.require(implNames.length == accessFlags.length || accessFlags.length == 1);
    for (uint256 i = implNames.length; i > 0; ) {
      i--;
      _accessRoles[implNames[i]] = i < accessFlags.length ? accessFlags[i] : accessFlags[0];
    }
  }

  function _onlyAccessibleImpl(bytes32 implName) private view {
    uint256 flags = _accessRoles[implName];
    if (flags != type(uint256).max) {
      // restricted access
      Access.require(flags == 0 ? isAdmin(msg.sender) : hasAnyAcl(msg.sender, flags));
    }
  }

  modifier onlyAccessibleImpl(bytes32 implName) {
    _onlyAccessibleImpl(implName);
    _;
  }

  function createProxy(
    address adminAddress,
    bytes32 implName,
    address ctx,
    bytes memory params
  ) external override onlyAccessibleImpl(implName) returns (address) {
    return address(_createProxy(adminAddress, getDefaultImplementation(implName, ctx), params, implName));
  }

  function createProxyWithImpl(
    address adminAddress,
    bytes32 implName,
    address impl,
    bytes calldata params
  ) external override onlyAccessibleImpl(implName) returns (address) {
    State.require(implName != 0 && implName == _authImpls[impl]);
    return address(_createProxy(adminAddress, impl, params, implName));
  }

  function _onlyAdminOrProxyOwner(address proxyAddress) private view {
    Access.require(getProxyOwner(proxyAddress) == msg.sender || isAdmin(msg.sender));
  }

  modifier onlyAdminOrProxyOwner(address proxyAddress) {
    _onlyAdminOrProxyOwner(proxyAddress);
    _;
  }

  function upgradeProxy(address proxyAddress, bytes calldata params) external override onlyAdminOrProxyOwner(proxyAddress) returns (bool) {
    address prevImpl = getProxyImplementation(proxyAddress);
    (bytes32 name, address ctx) = getImplementationType(prevImpl);
    address newImpl = getDefaultImplementation(name, ctx);
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
  ) external override onlyAdmin returns (bool) {
    address prevImpl = getProxyImplementation(proxyAddress);
    if (prevImpl != newImpl) {
      (bytes32 name, address ctx) = getImplementationType(prevImpl);
      (bytes32 name2, address ctx2) = getImplementationType(newImpl);
      Value.require(ctx == ctx2);
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
