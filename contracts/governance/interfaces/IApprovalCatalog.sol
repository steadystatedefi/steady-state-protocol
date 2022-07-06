// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IApprovalCatalog {
  struct ApprovedPolicy {
    bytes32 requestCid;
    bytes32 approvalCid;
    address insured;
    uint16 riskLevel;
    uint80 basePremiumRate;
    string policyName;
    string policySymbol;
    address premiumToken;
    uint96 minPrepayValue;
    uint32 rollingAdvanceWindow;
    uint32 expiresAt;
    bool applied;
  }

  function hasApprovedApplication(address insured) external view returns (bool);

  function getApprovedApplication(address insured) external view returns (ApprovedPolicy memory);

  function applyApprovedApplication() external returns (ApprovedPolicy memory);

  struct ApprovedClaim {
    bytes32 requestCid;
    bytes32 approvalCid;
    uint256 payoutValue;
    uint32 since;
  }

  function hasApprovedClaim(address insured) external view returns (bool);

  function getApprovedClaim(address insured) external view returns (ApprovedClaim memory);

  function applyApprovedClaim() external returns (ApprovedClaim memory);
}
