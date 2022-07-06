// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IJoinHandler.sol';
import './IApprovalCatalog.sol';

interface IInsurerGovernor is IJoinHandler {
  function governerQueryAccessControlMask(address subject, uint256 filterMask) external view returns (uint256);

  function verifyPayoutRatio(address insured, uint256 payoutRatio) external returns (uint256);

  function getApprovedPolicyForInsurer(address insured) external returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data);
}
