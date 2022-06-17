// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

// TODO rename it
interface IPremiumCalculator is ICollateralized {
  function totalPremium() external view returns (uint256 rate, uint256 demand);
}

interface ITokenPremiumCalculator {
  function convertPremium(
    address collateral,
    uint256 amount,
    address token
  ) external view returns (uint256);
}
