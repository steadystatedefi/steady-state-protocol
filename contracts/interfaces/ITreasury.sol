// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ITreasury {
  function borrowFunds(address token, uint128 amount) external;

  function depositFunds(address token, uint128 amount) external;
}

///@dev A strategy will deploy capital (can deploy multiple underlyings) and earn Earnings
/// the strategy may earn a different token than deposited underlying.
interface ITreasuryStrategy {
  ///@dev Represents earned value from a strategy. Does NOT give an indication when tokens lost
  struct Earning {
    address token;
    uint128 value;
  }

  ///@dev Returns all the earnings for an underlying
  ///@param token The token that is being invested to generate Earning(s)
  function totalEarningsOf(address token) external view returns (Earning[] memory);

  ///@dev Total amount of token earned or lost by this strategy
  ///@param token The token that was earned (not necessairly supplied, however you can only lose what is supplied)
  function deltaOf(address token) external view returns (int256);

  ///@dev Returns the amount of invested capital + amount it has earned
  ///@param token The token that supplied+earned
  function totalValue(address token) external view returns (uint128);

  ///@dev Request by the fund to return an amount of capital. The strategy SHALL return
  /// the most it can up to the amount
  ///@param token  Underlying to return
  ///@param amount      Amount requested to return
  ///@return            Whether any capital (even less than the requested amount) was sent
  function requestReturn(address token, uint128 amount) external returns (bool);

  ///@dev Get the cumulative WAD performance for the given token
  function cumulativePerformanceOf(address token) external view returns (int256);
}
