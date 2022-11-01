// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

/// @dev An interface of a contract responsible to collect prepayments of a premium token. It is implemented by insureds.
/// @dev Prepayments shoud be sent as regular ERC20 transfer.
interface IPremiumCollector {
  /// @return The premium token.
  function premiumToken() external view returns (address);

  /// @return amount of the premium token to be prepaid at the given (current or future) timestamp.
  function expectedPrepay(uint256 atTimestamp) external view returns (uint256);

  /// @return amount of the premium token to be prepaid after the given number of seconds since now.
  function expectedPrepayAfter(uint32 timeDelta) external view returns (uint256);

  /// @dev Withdraws available (not yet locked) prepaid balance.
  /// @param recipient to receive the transfer
  /// @param amount to be transferred. Excessive specific amount will revert, but type(uint256).max will take all balance available for withdraw.
  function withdrawPrepay(address recipient, uint256 amount) external;
}
