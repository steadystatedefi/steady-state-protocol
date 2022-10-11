// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface ICollateralCurrencyInit {
  function initializeCollateralCurrency(string memory name, string memory symbol) external;
}
