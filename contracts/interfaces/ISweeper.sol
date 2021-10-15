// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface ISweeper {
  /// @dev transfer ERC20 or ETH from the utility contract, for recovery of direct transfers to the contract address.
  function sweepToken(
    address token,
    address to,
    uint256 amount
  ) external;
}
