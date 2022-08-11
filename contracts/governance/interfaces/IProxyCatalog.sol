// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IProxyFactory.sol';

interface IProxyCatalog is IProxyFactory {
  function getImplementationType(address impl) external view returns (bytes32, address);

  function isAuthenticImplementation(address impl) external view returns (bool);

  function isAuthenticProxy(address proxy) external view returns (bool);

  function getDefaultImplementation(bytes32 name, address context) external view returns (address);

  function getProxyOwner(address proxy) external view returns (address);

  function getProxyImplementation(address proxy) external view returns (address);
}

interface IManagedProxyCatalog is IProxyCatalog {
  function addAuthenticImplementation(
    address impl,
    bytes32 name,
    address context
  ) external;

  function removeAuthenticImplementation(address impl, address defReplacement) external;

  function unsetDefaultImplementation(address impl) external;

  function setDefaultImplementation(address impl) external;

  event ImplementationAdded(bytes32 indexed name, address indexed context, address indexed impl);
  event ImplementationRemoved(bytes32 indexed name, address indexed context, address indexed impl);
  event DefaultImplementationUpdated(bytes32 indexed name, address indexed context, address indexed impl);
}
