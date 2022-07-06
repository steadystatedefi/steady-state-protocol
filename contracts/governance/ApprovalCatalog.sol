// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';
import '../tools/upgradeability/TransparentProxy.sol';
import '../tools/upgradeability/ProxyAdminBase.sol';
import '../tools/upgradeability/IProxy.sol';
import '../tools/upgradeability/IVersioned.sol';
import '../access/interfaces/IAccessController.sol';
import '../access/AccessHelper.sol';
import '../access/AccessFlags.sol';
import './interfaces/IApprovalCatalog.sol';
import './interfaces/IClaimAccessValidator.sol';
import './ProxyTypes.sol';

contract ApprovalCatalog is IApprovalCatalog, AccessHelper {
  bytes32 private immutable _insuredProxyType;
  IAccessController private immutable _acl;

  constructor(IAccessController acl, bytes32 insuredProxyType) {
    _acl = acl;
    _insuredProxyType = insuredProxyType;
  }

  function remoteAcl() internal view override returns (IAccessController) {
    return _acl;
  }

  struct RequestedPolicy {
    bytes32 cid;
    address requestedBy;
  }

  mapping(address => RequestedPolicy) private _requestedPolicies;
  mapping(address => ApprovedPolicy) private _approvedPolicies;

  event ApplicationSubmitted(address indexed insured, bytes32 indexed requestCid);

  function submitApplication(bytes32 cid) external returns (address insured) {
    State.require(!hasApprovedApplication(insured));

    insured = _createInsured(msg.sender);
    _submitApplication(insured, cid);
  }

  function _submitApplication(address insured, bytes32 cid) private {
    Value.require(cid != 0);
    _requestedPolicies[insured] = RequestedPolicy({cid: cid, requestedBy: msg.sender});
    emit ApplicationSubmitted(insured, cid);
  }

  function _createInsured(address requestedBy) private returns (address) {
    return getProxyFactory().createProxy(requestedBy, _insuredProxyType, ProxyTypes.insuredInit(remoteAcl(), requestedBy));
  }

  function resubmitApplication(address insured, bytes32 cid) external {
    State.require(!hasApprovedApplication(insured));

    _submitApplication(insured, cid);
  }

  function hasApprovedApplication(address insured) public view returns (bool) {
    return _approvedPolicies[insured].insured == insured;
  }

  function getApprovedApplication(address insured) external view returns (ApprovedPolicy memory) {
    State.require(hasApprovedApplication(insured));
    return _approvedPolicies[insured];
  }

  event ApplicationApplied(address indexed insured, bytes32 indexed requestCid);

  function applyApprovedApplication() external returns (ApprovedPolicy memory data) {
    address insured = msg.sender;
    State.require(hasApprovedApplication(insured));
    data = _approvedPolicies[insured];
    _approvedPolicies[insured].applied = true;

    emit ApplicationApplied(insured, data.requestCid);
  }

  function getAppliedApplicationForInsurer(address insured) external view returns (bool valid, ApprovedPolicyForInsurer memory data) {
    ApprovedPolicy storage policy = _approvedPolicies[insured];
    if (policy.insured == insured && policy.applied) {
      data = ApprovedPolicyForInsurer({riskLevel: policy.riskLevel, basePremiumRate: policy.basePremiumRate, premiumToken: policy.premiumToken});
      valid = true;
    }
  }

  event ApplicationApproved(address indexed insured, bytes32 indexed requestCid, ApprovedPolicy data);

  function approveApplication(ApprovedPolicy calldata data) external aclHas(AccessFlags.UNDERWRITER_POLICY) {
    Value.require(data.insured != address(0));
    Value.require(data.requestCid != 0);
    Value.require(!data.applied);
    State.require(!hasApprovedApplication(data.insured));
    _approvedPolicies[data.insured] = data;
    emit ApplicationApproved(data.insured, data.requestCid, data);
  }

  event ApplicationDeclined(address indexed insured, bytes32 indexed cid, string reason);

  function declineApplication(
    address insured,
    bytes32 cid,
    string calldata reason
  ) external aclHas(AccessFlags.UNDERWRITER_POLICY) {
    Value.require(insured != address(0));
    ApprovedPolicy storage data = _approvedPolicies[insured];
    if (data.insured != address(0)) {
      assert(data.insured == insured);
      if (data.requestCid == cid) {
        // decline of the previously approved one is only possible when is was not applied
        State.require(!data.applied);
        delete _approvedPolicies[insured];
      }
    }
    emit ApplicationDeclined(insured, cid, reason);
  }

  // struct RequestedPolicyExtension {
  //   address requestedBy;
  // }

  // struct ApprovedPolicyExtension {
  //   address insured;
  // }

  // function submitExtension(address insured) external {
  // }

  // function hasApprovedExtension(address insured) external view returns(bool) {
  //   return _approvedPolicies[insured].insured == insured;
  // }

  // function getApprovedExtension(address insured) external view returns(ApprovedPolicyExtension memory) {
  // }

  struct RequestedClaim {
    bytes32 cid; // supporting documents
    address requestedBy;
    uint256 payout;
  }

  mapping(address => RequestedClaim[]) private _requestedClaims;
  mapping(address => ApprovedClaim) private _approvedClaims;

  event ClaimSubmitted(address indexed insured, bytes32 indexed cid, uint256 payout);

  function submitClaim(
    address insured,
    bytes32 cid,
    uint256 payout
  ) external returns (uint256) {
    Value.require(cid != 0);
    Value.require(insured != address(0));
    State.require(!hasApprovedClaim(insured));
    Access.require(IClaimAccessValidator(insured).canClaimInsurance(msg.sender));

    RequestedClaim[] storage claims = _requestedClaims[insured];
    claims.push(RequestedClaim({cid: cid, requestedBy: msg.sender, payout: payout}));

    emit ClaimSubmitted(insured, cid, payout);

    return claims.length;
  }

  function hasApprovedClaim(address insured) public view returns (bool) {
    return _approvedClaims[insured].requestCid != 0;
  }

  function getApprovedClaim(address insured) public view returns (ApprovedClaim memory) {
    State.require(hasApprovedClaim(insured));
    return _approvedClaims[insured];
  }

  event ClaimApplied(address indexed insured, bytes32 indexed requestCid, ApprovedClaim data);

  function applyApprovedClaim(address insured) external returns (ApprovedClaim memory data) {
    data = getApprovedClaim(insured);
    emit ClaimApplied(insured, data.requestCid, data);
  }

  event ClaimApproved(address indexed insured, bytes32 indexed requestCid, ApprovedClaim data);

  function approveClaim(address insured, ApprovedClaim calldata data) external aclHas(AccessFlags.UNDERWRITER_CLAIM) {
    Value.require(insured != address(0));
    Value.require(data.requestCid != 0);
    State.require(!hasApprovedClaim(insured));
    _approvedClaims[insured] = data;
    emit ClaimApproved(insured, data.requestCid, data);
  }
}
