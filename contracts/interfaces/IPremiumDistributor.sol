// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

/// @dev An interface for an actuary (insurer) to work with a premium distributor (premium fund)
interface IPremiumDistributor is ICollateralized {
  /// @dev A callback when the premium supply was increased (i.e. coverage was increased). Only for a known actuary and a registered source.
  /// @param source is an insured
  /// @param accumulated is a total value of premium to be paid by the insured at this moment
  /// @param rate of a premium value to be paid by the insured per second since this moment
  function premiumAllocationUpdated(
    address source,
    uint256 accumulated,
    uint256 rate
  ) external;

  /// @dev A callback when the premium supply was stopped (i.e. coverage was cancelled). Only for a known actuary and a registered source.
  /// @dev This call will happen before registerPremiumSource(source, false).
  /// @param source is an insured
  /// @param accumulated is a total value of premium to be paid by the insured at this moment
  /// @return premiumDebt is a value of premium which was not paid by the insured
  function premiumAllocationFinished(address source, uint256 accumulated) external returns (uint256 premiumDebt);

  /// @dev A callback when a source (insured) was added (joined) or removed (left) the actuary (insurer). Only for a known actuary.
  /// @param source is an insured
  /// @param register is true to register the source and false to unregister it.
  function registerPremiumSource(address source, bool register) external;
}
