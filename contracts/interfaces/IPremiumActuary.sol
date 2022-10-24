// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

/// @dev An interface of a contract responsible to account for premium values. It is implemented by insurers.
interface IPremiumActuary is ICollateralized {
  /// @return an address of a premium distributor, i.e. PremiumFund
  function premiumDistributor() external view returns (address);

  /// @return maxDrawdownValue is a total drawdown value of this actuary
  /// @return availableDrawdownValue is drawdown value of this actuary which is usable (can be burnt)
  function collectDrawdownPremium() external returns (uint256 maxDrawdownValue, uint256 availableDrawdownValue);

  /// @dev Burns account's premium balance. Only for premiumDistributor().
  /// @param account to be burnt
  /// @param value to be burnt (CC-based)
  /// @param drawdownRecepient when non-zero, then also performs drawdown and sends 'value' of CC to the recipient.
  function burnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) external;
}
