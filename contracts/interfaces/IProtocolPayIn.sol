// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './IProtocol.sol';

/// @dev An abstraction for protocols to access information about balance, payments etc
interface IProtocolPayIn {
  struct TokenAmount {
    address token;
    uint256 amount;
  }

  /// @dev adds tokens to protocol's deposits. Protocol can only supply an agreed set of tokens, e.g. protocol's token & USDx
  /// @dev only users allowed by IProtocol.hasRole(DEPOSIT) can do this
  function deposit(address forProtocol, TokenAmount[] calldata amounts) external;

  /// @dev withdraws tokens from protocol's deposits.
  /// @dev only users allowed by IProtocol.hasRole(WITHDRAW) can do this
  function withdraw(address forProtocol, TokenAmount[] calldata amounts) external;

  /// @dev returns amounts that were not yet consumed/locked by the stream of premium
  function balanceOf(address protocol) external view returns (TokenAmount[] memory);

  /// @dev returns amounts expected to be consumed/locked by the stream of premium at atTimestamp in the future and starting from now
  function expectedPay(address protocol, uint32 atTimestamp) external view returns (TokenAmount[] memory);

  /// @dev returns current coverage stats
  function coverageOf(address protocol)
    external
    view
    returns (
      uint256 requestedCoverage,
      uint256 providedCoverage,
      address token
    );

  /// @dev returns an intergal of coverage ratio starting from the first premium payment till now.
  /// @dev value is <= 1.0, nominated in RAYS (1.0 is represented as 10^27). When coverage was always provided at 100% then the result is 1.0
  function coverageIndex() external returns (uint256);

  /// @dev returns an intergal of premium steadiness starting from the first premium payment till now
  /// @dev value is <= 1.0, nominated in RAYS (1.0 is represented as 10^27).
  /// @dev when deposits were always sufficient to cover premium stream, then the result is 1.0
  function payinIndex() external returns (uint256);
}
