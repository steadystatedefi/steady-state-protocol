// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import './ICoverageDistributor.sol';
import '../insurer/Rounds.sol';

interface IInsurerPoolBase is ICollateralized, ICharterable {
  /// @dev returns ratio of $IC to $CC, this starts as 1 (RAY)
  function exchangeRate() external view returns (uint256);
}

interface IPerpetualInsurerPool is IInsurerPoolBase {
  /// @notice The interest of the account is their earned premium amount
  /// @param account The account to query
  /// @return rate The current interest rate of the account
  /// @return accumulated The current earned premium of the account
  function interestOf(address account) external view returns (uint256 rate, uint256 accumulated);

  /// @notice Withdrawable amount of this account
  /// @param account The account to query
  /// @return amount The amount withdrawable
  function withdrawable(address account) external view returns (uint256 amount);

  /// @notice Attempt to withdraw all of a user's coverage
  /// @return The amount withdrawn
  function withdrawAll() external returns (uint256);
}

interface IInsurerPool is IERC20, IInsurerPoolBase, ICoverageDistributor {
  function statusOf(address) external view returns (MemberStatus);
}
