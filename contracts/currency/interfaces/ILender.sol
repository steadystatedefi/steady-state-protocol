// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface ILender is ICollateralized {
  function approveBorrow(
    address operator,
    address token,
    uint256 amount,
    address to
  ) external;

  function repayFrom(
    address token,
    address from,
    uint256 amount
  ) external;

  function depositYield(
    address token,
    address from,
    uint256 amount,
    address to
  ) external;

  function isBorrowOps(address) external view returns (bool);
}
