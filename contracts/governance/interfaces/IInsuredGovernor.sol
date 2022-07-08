// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IApprovalCatalog.sol';

interface IInsuredGovernor {
  function governerQueryAccessControlMask(address subject, uint256 filterMask) external view returns (uint256);

  // function getApprovedPolicyForInsurer(address insured) external returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data);
}
