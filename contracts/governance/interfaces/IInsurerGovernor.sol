// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IJoinHandler.sol';
import './IGovernorAccessBitmask.sol';
import './IApprovalCatalog.sol';

/// @dev Callbacks to the governor for operations of insurer.
/// @dev Requires ERC165
interface IInsurerGovernor is IGovernorAccessBitmask, IJoinHandler {
  /// @dev Allows the governor to check and override payout ratio for the insured.
  /// @dev This call back is NOT invoked on cancellation (with zero payout) and on enforced payouts.
  /// @param insured policy to be cancelled
  /// @param payoutRatio non-zero, from the ApprovalCatalog.
  /// @return payoutRatio to be applied.
  function verifyPayoutRatio(address insured, uint256 payoutRatio) external returns (uint256);

  /// @dev Allows the governor to accept insured policies (and provide parameters) directly, not through the ApprovalCatalog.
  /// @param insured policy to be joined
  /// @return ok is true to use policy params from this function. Otherwise, params will be requested from the ApprovalCatalog.
  /// @return data with params for the policy. Ignored when ok is false.
  function getApprovedPolicyForInsurer(address insured) external returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data);
}
