// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IProxyFactory {
  /// @return true when the proxy is known and its current implementation is authentic
  function isAuthenticProxy(address proxy) external view returns (bool);

  /// @dev Creates a proxy using default implementation of the given type name and context.
  /// @dev Will revert when a default implementation is missing.
  /// @param adminAddress is an address only allowed to upgrade the proxy. Zero means owner/admin of the catalog.
  /// @param implName is a type name to look up an implementation.
  /// @param context is a context to look up an implementation.
  /// @param params is an encoded initialization call, zero length implies no init call
  /// @return an address of the proxy created, also emits ProxyCreated
  function createProxy(
    address adminAddress,
    bytes32 implName,
    address context,
    bytes calldata params
  ) external returns (address);

  /// @dev Creates a proxy using the given implementation.
  /// @dev Will revert when a default implementation is missing.
  /// @param adminAddress is an address allowed to upgrade the proxy. Can be zero.
  /// @param implName is a type name of the implementation.
  /// @param impl is the implementation - it must be added as authentic for the given type.
  /// @param params is an encoded initialization call, zero length implies no init call
  /// @return an address of the proxy created, also emits ProxyCreated
  function createProxyWithImpl(
    address adminAddress,
    bytes32 implName,
    address impl,
    bytes calldata params
  ) external returns (address);

  /// @dev Upgrades the proxy with the default implementation when it is has a higher revision.
  /// @dev Owner/admin of the catalog and admin of the proxy are allowed to call this function. See createProxy(), param `adminAddress`.
  /// @dev This function looks up type and context of the current impl of the proxy and takes a default impl by these type and context.
  /// @dev When the found default impl is different from the current one, the upgrade will be attempted.
  /// @dev The function will revert on an attempt of downgrade (when the new revision is not greater than the current one).
  /// @param proxyAddress to be upgraded.
  /// @param params is an encoded initialization call applied after the upgrade, zero length implies no init call.
  /// @return true when the proxy was upgraded and false when the implementation is the same.
  function upgradeProxy(address proxyAddress, bytes calldata params) external returns (bool);

  /// @dev Upgrades the proxy with the given implementation. Only owner/admin of the catalog can call it.
  /// @dev This function allows non-authentic/unknown implementations.
  /// @param proxyAddress to be upgraded.
  /// @param newImpl is a new implementation.
  /// @param checkRevision when is true and both implementations are known, then types, context and revisions are checked accordingly.
  /// @param params is an encoded initialization call applied after the upgrade, zero length implies no init call.
  /// @return true when the proxy was upgraded and false when the implementation is the same.
  function upgradeProxyWithImpl(
    address proxyAddress,
    address newImpl,
    bool checkRevision,
    bytes calldata params
  ) external returns (bool);

  event ProxyCreated(address indexed proxy, address indexed impl, string typ, bytes params, address indexed admin);
  event ProxyUpdated(address indexed proxy, address indexed impl, string typ, bytes params);
}
