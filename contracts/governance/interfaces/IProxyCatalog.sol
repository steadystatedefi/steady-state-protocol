// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IProxyFactory.sol';

interface IProxyCatalog is IProxyFactory {
  /// @return type name and context for the given implementation if it was ever added (i.e. works even for removed implementations).
  function getImplementationType(address impl) external view returns (bytes32, address);

  /// @return true when the implementation was added and was not removed
  function isAuthenticImplementation(address impl) external view returns (bool);

  /// @return true when the proxy was created by this factory and the proxy's current implementation is authentic (added, not removed)
  function isAuthenticProxy(address proxy) external view returns (bool);

  /// @return a default implementation for the given type `name` and `context`. Will revert when the implementation is missing.
  function getDefaultImplementation(bytes32 name, address context) external view returns (address);

  /// @dev Returns zero when the proxy was not created by this catalog.
  /// @dev Returns the address of this catalog when the proxy can be upgraded by the admin/owner of the relevant AccessController.
  /// @return an address which is allowed to upgrade the proxy through this catalog
  function getProxyOwner(address proxy) external view returns (address);

  /// @return an implementation of the proxy created by this catalog. Will not revert but return zero for other cases.
  function getProxyImplementation(address proxy) external view returns (address);
}

interface IManagedProxyCatalog is IProxyCatalog {
  /// @dev Registers `impl` as an authentic implementation for the type `name` and `context`.
  function addAuthenticImplementation(
    address impl,
    bytes32 name,
    address context
  ) external;

  /// @dev Makes the `impl` to be non-authentic, i.e. unusable for to create or upgrade a proxy.
  /// @param impl to be marked as non-authentic.
  /// @param defReplacement applied as default when the `impl` is default. Must be zero, or an authentic with the same type and context as the impl.
  function removeAuthenticImplementation(address impl, address defReplacement) external;

  /// @dev Unsets the `impl` when is it set as a default for its type and context. Will not revert when the impl is undknown or is not a default one.
  function unsetDefaultImplementation(address impl) external;

  /// @dev Sets the `impl` as a default for its type and context. Will revert when the impl is not authentic one.
  function setDefaultImplementation(address impl) external;

  /// @dev Sets roles allowed to create a proxy of the given typeNames
  /// @dev By default (i.e. accessFlag = 0), only admin/owner of the relevant AccessController can create a proxy of a type.
  /// @dev Anyone can create a proxy when accessFlag = type(uint256).max.
  /// @dev Otherwise, only a caller with any roles defined by accessFlag will be allowed to create a proxy.
  /// @param typeNames with a list of types to set access flags, names can be any, except zero.
  /// @param accessFlags access flags corresponding to the types
  function setAccess(bytes32[] calldata typeNames, uint256[] calldata accessFlags) external;

  /// @return accessFlags for the given types, unknown types will return zero
  function getAccess(bytes32[] calldata typeNames) external view returns (uint256[] memory accessFlags);

  event ImplementationAdded(bytes32 indexed name, address indexed context, address indexed impl);
  event ImplementationRemoved(bytes32 indexed name, address indexed context, address indexed impl);
  event DefaultImplementationUpdated(bytes32 indexed name, address indexed context, address indexed impl);
}
