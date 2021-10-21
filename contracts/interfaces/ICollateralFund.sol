// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface ICollateralFund {
  /// @dev mints relevant IDepositToken, increases healthFactor and collateral balance ($CC)
  function deposit(
    address asset,
    uint256 amount,
    address to,
    uint256 referralCode
  ) external;

  /// @dev burns some of IDepositToken related to the asset when there in an excess of collateral.
  /// Decreases healthFactor, can't push healthFactor below 1.
  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external;

  /// @dev transfers available collateral to the given insurer pool. Decreases healthFactor, can't push healthFactor below 1.
  function invest(address insurer, uint256 amount) external;

  /// @dev transfers available collateral to the given insurer pool. Decreases healthFactor, can't push healthFactor below 1.
  function investWithParams(
    address insurer,
    uint256 amount,
    bytes calldata params
  ) external;

  /// @dev positive collateral balance ($CC), on negative returns zero
  function balanceOf(address account) external view returns (uint256);

  /// @dev invested collateral ($CC) plus any positive surplus from fund's liquidity, can not be less than investedCollateral()
  function totalSupply() external view returns (uint256);

  /// @dev similar to invest() function for user, can only transfer to insurer pools. Can't push healthFactor below 1.
  /// An insurer pool can transfer to both user and insured
  /// An insured pool - TBC
  function transfer(address to, uint256 amount) external view returns (uint256);

  /// @dev healthFactor and signed balance. healthFactor is in RAY
  function healthFactorOf(address account) external view returns (uint256 hf, int256 balance);

  /// @dev amount of collateral ($CC) given out to insurer funds
  function investedCollateral() external view returns (uint256);

  /// @dev current performance of collateral and time-accumulated value of it
  function collateralPerformance() external view returns (uint256 rate, uint256 accumulated);

  function getReserveAssets() external view returns (address[] memory assets, address[] memory depositTokens);

  /// @dev can only be called by insured pool to cancel all coverage from the insurer.
  /// calls insusrer.onCoverageDeclined, then transfers back all $CC from caller (insured) to insurer
  function declineCoverageFrom(address insurer) external;
}

/// @dev ERC20 that represents a deposit of the given underlying. Can be transferred, but only while healthFactor stays above 1
interface IDepositToken {
  function getUnderlying() external view returns (address);
}
