// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IPremiumSource is ICollateralized {
  function collectPremium(address token, uint256 amount) external;
}
