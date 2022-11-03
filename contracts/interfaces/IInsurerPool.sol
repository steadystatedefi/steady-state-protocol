// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import './ICoverageDistributor.sol';
import '../insurer/Rounds.sol';

interface IInsurerPoolBase is ICollateralized, ICharterable {}

interface IInsurerToken is IInsurerPoolBase {
  /// @dev returns balances of a user
  /// @return value The value of the pool share tokens (and provided coverage)
  /// @return balance The number of the pool share tokens
  /// @return swappable The amount of user's value which can be swapped to tokens (e.g. premium earned)
  function balancesOf(address account)
    external
    view
    returns (
      uint256 value,
      uint256 balance,
      uint256 swappable
    );

  /// @return CC-equivalent value of this pool
  function totalSupplyValue() external view returns (uint256);

  /// @return RAY-based ratio of totalSupplyValue() to totalSupply(), i.e. a value of a pool's share.
  function exchangeRate() external view returns (uint256);
}

interface IPerpetualInsurerPool is IInsurerToken {
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

interface IInsurerPool is IInsurerToken, ICoverageDistributor {
  /// @return status of the address
  function statusOf(address) external view returns (MemberStatus);
}
