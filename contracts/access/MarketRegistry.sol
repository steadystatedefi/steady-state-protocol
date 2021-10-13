// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/SafeOwnable.sol';
import '../tools/Errors.sol';
import './interfaces/IMarketRegistry.sol';

contract MarketRegistry is SafeOwnable, IMarketRegistry {
  struct Entry {
    uint256 id;
    uint16 index;
  }
  mapping(address => Entry) private _index;
  address[] private _providers;

  address private _oneTimeRegistrar;
  uint256 private _oneTimeId;

  function setOneTimeRegistrar(address registrar, uint256 expectedId) external override onlyOwner {
    _oneTimeId = expectedId;
    _oneTimeRegistrar = registrar;
  }

  function renounceOneTimeRegistrar() external override {
    if (_oneTimeRegistrar == msg.sender) {
      _oneTimeRegistrar = address(0);
    }
  }

  function getOneTimeRegistrar() external view override returns (address user, uint256 expectedId) {
    if (_oneTimeRegistrar == address(0)) {
      return (address(0), 0);
    }
    return (_oneTimeRegistrar, _oneTimeId);
  }

  /// @dev returns the list of registered providers, may contain zero elements
  function list() external view override returns (address[] memory activeProviders) {
    return _providers;
  }

  function prepareMarketRegistration(address provider) external override {
    require(msg.sender == _oneTimeRegistrar || msg.sender == owner(), Errors.TXT_OWNABLE_CALLER_NOT_OWNER);
    require(provider != address(0) && _index[provider].index == 0, Errors.MARKET_PROVIDER_NOT_REGISTERED);
    emit MarketProviderPreparing(provider);
  }

  /**
   * @dev Registers an addresses provider
   * @param provider The address of the new MarketProvider
   * @param id The id for the new MarketProvider, referring to the market it belongs to
   **/
  function registerMarketProvider(address provider, uint256 id) external override {
    if (msg.sender == _oneTimeRegistrar) {
      require(_oneTimeId == 0 || _oneTimeId == id, Errors.INVALID_MARKET_PROVIDER_ID);
      _oneTimeRegistrar = address(0);
    } else {
      require(msg.sender == owner(), Errors.TXT_OWNABLE_CALLER_NOT_OWNER);
      require(id != 0, Errors.INVALID_MARKET_PROVIDER_ID);
    }

    require(provider != address(0), Errors.MARKET_PROVIDER_NOT_REGISTERED);

    if (_index[provider].index > 0) {
      _index[provider].id = id;
    } else {
      require(_providers.length < type(uint16).max);
      _providers.push(provider);
      _index[provider] = Entry(id, uint16(_providers.length));
    }

    emit MarketProviderRegistered(provider, id);
  }

  /// @dev removes the MarketProvider from the list of registered providers
  function unregisterMarketProvider(address provider) external override onlyOwner {
    uint256 idx = _index[provider].index;
    require(idx != 0, Errors.MARKET_PROVIDER_NOT_REGISTERED);

    delete (_index[provider]);
    if (idx == _providers.length) {
      _providers.pop();
    } else {
      _providers[idx - 1] = address(0);
    }
    for (; _providers.length > 0 && _providers[_providers.length - 1] == address(0); ) {
      _providers.pop();
    }

    emit MarketProviderUnregistered(provider);
  }

  /// @dev returns the id on a registered MarketProvider or zero if not registered
  function getMarketProviderId(address provider) external view override returns (uint256) {
    return _index[provider].id;
  }
}
