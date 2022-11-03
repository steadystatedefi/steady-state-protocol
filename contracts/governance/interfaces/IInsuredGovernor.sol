// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IApprovalCatalog.sol';
import './IGovernorAccessBitmask.sol';

/// @dev Callbacks to the governor for operations of insured.
/// @dev Requires ERC165
interface IInsuredGovernor is IGovernorAccessBitmask {

}
