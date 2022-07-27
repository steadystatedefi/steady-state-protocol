// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface ICollateralStakeManager {
  function verifyBorrowUnderlying(address account, uint256 value) external returns (bool);

  function verifyRepayUnderlying(address account, uint256 value) external returns (bool);

  function syncStakeAsset(address asset) external;

  function syncByStakeAsset(uint256 assetSupply, uint256 collateralSupply) external;
}
