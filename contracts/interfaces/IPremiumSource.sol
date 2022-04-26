// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IPremiumSource {
  function pullPremiumSource(address insurer, uint256 expectedRefillAmount) external returns (uint256 value, uint256 amount);

  function transferPremium(
    address insurer,
    address to,
    uint256 amount
  ) external;
}
