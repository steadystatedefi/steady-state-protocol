// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IPremiumSource {
  function premiumToken() external view returns (address);

  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external;
}

interface IPremiumSourceDelegate {
  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value,
    address recipient
  ) external;
}
