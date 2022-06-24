// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IPremiumCollector {
  /// @return The token of premium
  function premiumToken() external view returns (address);

  function expectedPrepay(uint256 atTimestamp) external view returns (uint256); // amount or value?

  function expectedPrepayAfter(uint32 timeDelta) external view returns (uint256);

  function withdrawPrepay(address recipient, uint256 amount) external; // amount or value?
}
