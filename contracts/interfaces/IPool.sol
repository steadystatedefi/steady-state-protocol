// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// Keeping this in the same file for now for ease of reference
/// @dev Interface specified
interface IPool {
  //function getPoolToken() external view returns (address);
  function deposit(uint256 amount) external;

  function getPoolValue() external view returns (uint256);
}
