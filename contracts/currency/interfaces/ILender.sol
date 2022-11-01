// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

/// @dev An interface for a provider of liquidity borrowable for reinvestment
interface ILender is ICollateralized {
  /// @dev Approves transferFrom of `amount` of `token` by contract `to`
  /// @dev The the allowance given by this call must be fully consumed within the same tx as this call.
  /// @dev Implementation must revert when allowance for `to` is not zero.
  /// @param operator is an initiator of the borrowing
  /// @param token to be borrowed
  /// @param amount to be borrowed
  /// @param to a caller of further transferFrom
  function approveBorrow(
    address operator,
    address token,
    uint256 amount,
    address to
  ) external;

  /// @dev Returns a borrowing (fully or partially) of `amount` of `token` from a contract `from`.
  /// @dev Implementation must call transferFrom for the given amount.
  function repayFrom(
    address token,
    address from,
    uint256 amount
  ) external;

  /// @dev Converts yield given as `amount` of `token` from a contract `from` and transfers it to a contract `to`.
  /// @dev Implementation must call transferFrom for the given amount.
  function depositYield(
    address token,
    address from,
    uint256 amount,
    address to
  ) external;

  /// @dev Checks when the given address can initiate borrowing. The same address is given to `approveBorrow` as `operator`.
  function isBorrowOps(address) external view returns (bool);
}
