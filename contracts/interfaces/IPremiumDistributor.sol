// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IPremiumDistributor is ICollateralized {
  function premiumAllocationUpdated(
    address insured,
    uint256 accumulated,
    uint256 rate
  ) external;

  function premiumAllocationFinished(address insured, uint256 accumulated) external returns (uint256 premiumDebt);

  function registerPremiumSource(address insured, bool register) external;
}
