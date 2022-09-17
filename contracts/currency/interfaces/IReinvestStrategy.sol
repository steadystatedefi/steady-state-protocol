// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface IReinvestStrategy {
  function investFrom(
    address token,
    address from,
    uint256 amount
  ) external;

  function approveDivest(
    address token,
    address to,
    uint256 amount
  ) external;
}
