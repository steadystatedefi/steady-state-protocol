// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface IReinvestStrategy {
  function investFrom(
    address token,
    address from,
    uint256 amount
  ) external;

  ///@param amount The amount of token requesting to be withdrawn
  ///@param minLimit The minimum amount that must be left in the strategy after this withdraw
  function approveDivest(
    address token,
    address to,
    uint256 amount,
    uint256 minLimit
  ) external returns (uint256 amountBefore);

  function investedValueOf(address token) external view returns (uint256);
}
