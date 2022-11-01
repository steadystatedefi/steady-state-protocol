// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

/// @dev A strategy to reinvest tokens into a specific platform/protocol, e.g. to AAVE
interface IReinvestStrategy {
  /// @dev Invoked before first use of this strategy by the reinvestment manager. Can be invoked a few times.
  /// @param manager is an address of the reinvestment manager.
  /// @return true when the manager is acceptable.
  function attachManager(address manager) external returns (bool);

  /// @dev Invoked before `investFrom` when there is zero amount of `token` invested into this strategy by the caller (manager).
  /// @param token is an address of the token to be invested.
  /// @return true the `token` is supported and false otherwise.
  function connectAssetBefore(address token) external returns (bool);

  /// @dev Invoked after `investFrom` when `connectAssetBefore` was invoked before it.
  /// @param token is an address of the token invested.
  function connectAssetAfter(address token) external;

  /// @dev Invests the given `amount` of `token`, the amount must be taken in full from address `from` by transferFrom.
  function investFrom(
    address token,
    address from,
    uint256 amount
  ) external;

  /// @dev Dinvests the `token` and approves transferFrom for address `to`.
  /// @dev Implementation must calculate divested amount as min(max(0, amountBefore - minLimit), amount).
  /// @dev This caclulated amount should be approved for transferFrom for address `to`.
  /// @param amount The maximum amount of token for divestment.
  /// @param minLimit The minimum amount that must be left in the strategy after this divestment.
  /// @return amountBefore of token invested by this strategy before this devestment is applied.
  function approveDivest(
    address token,
    address to,
    uint256 amount,
    uint256 minLimit
  ) external returns (uint256 amountBefore);

  /// @return current amount of `token` invested through this strategy including all available gains and losses
  function investedValueOf(address token) external view returns (uint256);

  /// @dev A name of this strategy
  function name() external view returns (string memory);
}
