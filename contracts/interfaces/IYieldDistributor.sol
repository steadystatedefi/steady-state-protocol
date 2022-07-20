// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IYieldDistributor is ICollateralized {
  function reportEffectiveCollateralBalance(uint256 balance) external returns (uint256 yieldBalance, uint256 yieldRate);
}
