// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeOwnable.sol';
import '../tools/Errors.sol';
import '../tools/math/BitUtils.sol';
import '../tools/upgradeability/TransparentProxy.sol';
import '../tools/upgradeability/ProxyAdminBase.sol';
import '../tools/upgradeability/IProxy.sol';
import './interfaces/IAccessController.sol';
import './interfaces/IManagedAccessController.sol';

contract ProxyRegistry is ProxyAdminBase {
  using BitUtils for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  IAccessController private immutable _remoteAcl;

  mapping(address => address) private _proxies;

  mapping(bytes32 => address) private _defImpls;
  mapping(address => bytes32) private _implNames;

  constructor(IAccessController remoteAcl) {
    _remoteAcl = remoteAcl;
  }

  function _onlyAdmin() private view {
    Access.require(_remoteAcl.isAdmin(msg.sender));
  }

  modifier onlyAdmin() {
    _onlyAdmin();
    _;
  }

  function getDefaultImplementation(bytes32 name) public view returns (address) {
    return _defImpls[name];
  }

  function setDefaultImplementation(bytes32 name, address impl) public onlyAdmin {
    Value.require(impl != address(0));
    _implNames[impl] = name;
    _defImpls[name] = impl;
  }

  /// @dev Returns the current implementation of `proxy`.
  function getProxyAdmin(address proxy) public view virtual returns (address) {
    return _proxies[proxy];
  }

  /// @dev Returns the current implementation of `proxy`.
  function getProxyImplementation(address proxy) public view virtual returns (address) {
    return _getProxyImplementation(IProxy(proxy));
  }

  function setProxyImplementation(address proxy, address implAddress) public onlyAdmin {
    _updateImpl(proxy, implAddress, abi.encodeWithSignature('initialize(address)', address(_remoteAcl)));
    // emit AddressSet(id, implAddress, true);
  }

  function setProxyImplementationWithParams(
    address proxy,
    address implAddress,
    bytes calldata params
  ) public onlyAdmin {
    _updateImpl(proxy, implAddress, params);
    // emit AddressSet(id, implAddress, true);
  }

  /**
   * @dev Internal function to update the implementation of a specific proxied component of the protocol
   * - If there is no proxy registered in the given `id`, it creates the proxy setting `newAdress`
   *   as implementation and calls a function on the proxy.
   * - If there is already a proxy registered, it updates the implementation to `newAddress` by
   *   the upgradeToAndCall() of the proxy.
   * @param proxyAddress The the proxy to be updated or 0 to create a new one
   * @param newAddress The address of the new implementation
   * @param params The address of the new implementation
   **/
  function _updateImpl(
    address proxyAddress,
    address newAddress,
    bytes memory params
  ) private returns (address) {
    if (proxyAddress != address(0)) {
      // TODO require(_proxies & id != 0, 'use of setAddress is required');
      TransparentProxy(payable(proxyAddress)).upgradeToAndCall(newAddress, params);
    } else {
      proxyAddress = address(_createProxy(address(this), newAddress, params));
    }
    // emit ProxyCreated(id, proxyAddress);
    return proxyAddress;
  }

  function _createProxy(
    address adminAddress,
    address implAddress,
    bytes memory params
  ) private returns (TransparentProxy) {
    Value.require(adminAddress != address(0));
    TransparentProxy proxy = new TransparentProxy(adminAddress, implAddress, params);
    _proxies[address(proxy)] = adminAddress;
    return proxy;
  }

  function createProxy(
    address adminAddress,
    address implAddress,
    bytes calldata params
  ) external returns (IProxy) {
    return _createProxy(adminAddress, implAddress, params);
  }

  // function createDefaultProxy(
  //   bytes32 implName,
  //   bytes calldata params
  // ) external returns (IProxy) {
  //   return _createProxy(adminAddress, implAddress, params);
  // }
}
