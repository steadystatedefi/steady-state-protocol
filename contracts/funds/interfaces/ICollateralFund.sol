// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface ICollateralFund is ICollateralized {
  function setApprovalsFor(
    address operator,
    uint256 access,
    bool approved
  ) external;

  function setAllApprovalsFor(address operator, uint256 access) external;

  function getAllApprovalsFor(address account, address operator) external view returns (uint256);

  function isApprovedFor(
    address account,
    address operator,
    uint256 access
  ) external view returns (bool);

  function deposit(
    address account,
    address token,
    uint256 tokenAmount
  ) external returns (uint256);

  function invest(
    address account,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external returns (uint256);

  function investIncludingDeposit(
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external returns (uint256);

  function withdraw(
    address account,
    address to,
    address token,
    uint256 amount
  ) external returns (uint256);

  function assets() external view returns (address[] memory);
}
