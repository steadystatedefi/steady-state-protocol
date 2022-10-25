// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

/// @dev An interface of a contract responsible to provide a premium token to a premium distributor. It is implemented by insureds.
interface IPremiumSource {
  /// @return the premium token given to the premiumd distributor by this source
  function premiumToken() external view returns (address);

  /// @dev Pulls premium from this source. The premium token is transferred to the caller.
  /// @dev Only for premium distributor of a known insurer (actuary).
  /// @param actuary is an insurer on behalf of which the token is pulled.
  /// @param token of premium to be pulled.
  /// @param amount is an expected amount. The actual tranferred amount can be different.
  /// @param value is a value equivalent of the amount.
  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external;
}
