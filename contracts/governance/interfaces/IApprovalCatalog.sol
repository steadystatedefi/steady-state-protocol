// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Contract access to an oracle facilitating interactions with off-line underwriters.
/// @dev Currently 2 subjects are supported: (1) An application for insurance policy; and (2) a claim for insurance payout.
interface IApprovalCatalog {
  /// @dev Information about the approved insurance policy, provided by an underwriter for an application.
  struct ApprovedPolicy {
    /// @dev Content hash of a document with the application for the insurance policy (provided by an applicant). Not zero.
    bytes32 requestCid;
    /// @dev Content hash of a document with the approval and T&C for an insurance policy (provided by an underwriter)
    bytes32 approvalCid;
    /// @dev Address of the insured contract, it is also a key to the application and the approval.
    address insured;
    /// @dev Risk level estimate provided by an underwriter. For insurers to calculate coverage shares.
    uint16 riskLevel;
    /// @dev A minimum premium rate for the insured. An insurer will not accept demand coverage with a lower rate.
    uint80 basePremiumRate;
    /// @dev Name of the policy (also it is a name for the rate share of the insured)
    string policyName;
    /// @dev Symbol for the rate share token of the insured.
    string policySymbol;
    /// @dev A token for the policy to pay premium. Must have a price source known.
    address premiumToken;
    /// @dev Initial amount of CC-based value of premium token to be prepaid by a policy holder to use this approval.
    uint96 minPrepayValue;
    /// @dev A time (a number of seconds) for the premium to be paid in advance.
    uint32 rollingAdvanceWindow;
    /// @dev Expiration of the insurance policy. Must be handled off-chain.
    uint32 expiresAt;
    /// @dev Internal use. Indicates when this approval was applied.
    bool applied;
  }

  /// @dev A subset of ApprovedPolicy required by insurers to accept a joining insured.
  struct ApprovedPolicyForInsurer {
    /// @dev Same as ApprovedPolicy.riskLevel
    uint16 riskLevel;
    /// @dev Same as ApprovedPolicy.basePremiumRate
    uint80 basePremiumRate;
    /// @dev Same as ApprovedPolicy.premiumToken
    address premiumToken;
  }

  /// @return true when there is an approved application for the `insured`
  function hasApprovedApplication(address insured) external view returns (bool);

  /// @return an approved application for the `insured` or reverts otherwise
  function getApprovedApplication(address insured) external view returns (ApprovedPolicy memory);

  /// @dev Markes the application for msg.sender as applied, and returns it.
  /// @dev Reverts when the application is missing, is not approved or was already applied.
  /// @return an approved application for msg.sender as an insured
  function applyApprovedApplication() external returns (ApprovedPolicy memory);

  /// @dev Looks up and returns a small portion of the application by the `insured`.
  /// @return valid as true when the approved application is available and it was applied, or false otherwise.
  /// @return data subset from the application when valid is true.
  function getAppliedApplicationForInsurer(address insured) external view returns (bool valid, ApprovedPolicyForInsurer memory data);

  /// @dev Information about the approved insurance claim, provided by an underwriter.
  struct ApprovedClaim {
    /// @dev Content hash of a document with the insurance claim (provided by an applicant). Not zero.
    bytes32 requestCid;
    /// @dev Content hash of a document with the claim approval and T&C (provided by an underwriter),
    bytes32 approvalCid;
    /// @dev A maximum percentage of coverage, which can be requested as a payout. 100% = 10_000
    uint16 payoutRatio;
    /// @dev A timestamp, starting from which, the claim can be executed.
    uint32 since;
  }

  /// @return true when there is an approved claim for the `insured`
  function hasApprovedClaim(address insured) external view returns (bool);

  /// @return an approved claim for the `insured` or reverts otherwise
  function getApprovedClaim(address insured) external view returns (ApprovedClaim memory);

  /// @dev Markes the claim for the `insured` as applied, and returns it.
  /// @dev Reverts when the claim is missing, is not approved or was (optionally) already applied.
  /// @return an approved claim for the `insured`
  function applyApprovedClaim(address insured) external returns (ApprovedClaim memory);
}
