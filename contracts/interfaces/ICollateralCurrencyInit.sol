// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Initialization for a collateral currency proxy
interface ICollateralCurrencyInit {
  /// @param name for ERC20
  /// @param symbol for ERC20
  function initializeCollateralCurrency(string memory name, string memory symbol) external;
}
