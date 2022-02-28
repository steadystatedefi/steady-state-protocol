// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ITreasury {
  function borrowFunds(address token, uint128 amount) external;

  function depositFunds(address token, uint128 amount) external;
}

///@dev A strategy will deploy capital (can deploy multiple underlyings) and earn Earnings
/// the strategy may earn a different token than deposited underlying.
interface ITreasuryStrategy {
  ///@dev Represents earned value from a strategy
  struct Earning {
    address token;
    uint128 value;
  }

  ///@dev Returns all the earnings for an underlying
  ///@param underlying The token that is being invested to generate Earning(s)
  function totalEarningsOf(address underlying) external view returns (Earning[] memory);

  ///@dev Total amount of token earned by this strategy
  ///@param token The token that was earned (not supplied)
  function totalEarned(address token) external view returns (uint128);

  ///@dev Returns the amount of invested capital + amount it has earned
  ///@param token The token that supplied+earned
  function totalValue(address token) external view returns (uint128);

  ///@dev Request by the fund to return an amount of capital. The strategy SHALL return
  /// the most it can up to the amount
  ///@param underlying  Underlying to return
  ///@param amount      Amount requested to return
  ///@return            Whether any capital (even less than the requested amount) was sent
  function requestReturn(address underlying, uint128 amount) external returns (bool);
}
