// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Escrow sub-balances for a token
interface ISubBalance {
  /// @dev Enables use of the given account for escrow. It will get a sub-balance for escrow between the account and the caller.
  /// @dev The escrow sub-balance can not be transferred or burnt.
  function openSubBalance(address account) external;

  /// @dev Closes escrow sub-balance between the account and the caller.
  /// @param transferAmount will be transferred from the escrow sub-balance to the account, and the rest will be returned to the caller.
  function closeSubBalance(address account, uint256 transferAmount) external;

  /// @return amount on the escrow sub-balance created by `from` for `account`.
  function subBalanceOf(address account, address from) external view returns (uint256);

  /// @return full is the total amount of the `account` including escrow (givenIn)
  /// @return givenOut is the amount given out by the `account` as escrows
  /// @return givenIn is the amount received by the `account` as escrows
  function balancesOf(address account)
    external
    view
    returns (
      uint256 full,
      uint256 givenOut,
      uint256 givenIn
    );
}
