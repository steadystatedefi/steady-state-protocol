// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface ILender is ICollateralized {
  function borrow(
    address token,
    uint256 amount,
    address to
  ) external;

  function repay(address token, uint256 amount) external;
}
