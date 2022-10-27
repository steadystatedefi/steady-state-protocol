// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Initialization for an insured pool (policy)
interface IInsuredPoolInit {
  /// @param governor for the insured pool (policy)
  function initializeInsured(address governor) external;
}
