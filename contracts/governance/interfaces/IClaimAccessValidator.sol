// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Interface to check a caller on ApprovalCatalog.submitClaim()
interface IClaimAccessValidator {
  /// @return true when the given address can claim insurance for the callee.
  function canClaimInsurance(address) external view returns (bool);
}
