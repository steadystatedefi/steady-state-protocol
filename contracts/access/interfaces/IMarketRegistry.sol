// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IRemoteAccessBitmask.sol';
import '../../tools/upgradeability/IProxy.sol';

interface IMarketRegistry {
  event MarketProviderPreparing(address provider);
  event MarketProviderRegistered(address provider, uint256 id);
  event MarketProviderUnregistered(address provider);

  function setOneTimeRegistrar(address registrar, uint256 expectedId) external;

  function renounceOneTimeRegistrar() external;

  function getOneTimeRegistrar() external view returns (address user, uint256 expectedId);

  function list() external view returns (address[] memory activeProviders);

  function prepareMarketRegistration(address provider) external;

  function registerMarketProvider(address provider, uint256 id) external;

  function unregisterMarketProvider(address provider) external;

  function getMarketProviderId(address provider) external view returns (uint256);
}
