// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';
import '../tools/upgradeability/TransparentProxy.sol';
import '../tools/upgradeability/ProxyAdminBase.sol';
import '../tools/upgradeability/IProxy.sol';
import '../tools/upgradeability/IVersioned.sol';
import '../tools/EIP712Lib.sol';
import '../access/interfaces/IAccessController.sol';
import '../access/AccessHelper.sol';
import '../access/AccessFlags.sol';
import './interfaces/IApprovalCatalog.sol';
import './interfaces/IClaimAccessValidator.sol';
import './ProxyTypes.sol';

contract ApprovalCatalog is IApprovalCatalog, AccessHelper {
  // solhint-disable-next-line var-name-mixedcase
  bytes32 public DOMAIN_SEPARATOR;

  bytes32 public constant APPROVE_APPL_TYPEHASH = keccak256('approveApplicationByPermit');
  bytes32 public constant APPROVE_CLAIM_TYPEHASH = keccak256('approveClaimByPermit');

  bytes32 private immutable _insuredProxyType;

  constructor(IAccessController acl, bytes32 insuredProxyType) AccessHelper(acl) {
    _insuredProxyType = insuredProxyType;
    // _initializeDomainSeparator();
  }

  mapping(address => uint256) private _nonces;

  /// @dev returns nonce, to comply with eip-2612
  function nonces(address addr) external view returns (uint256) {
    return _nonces[addr];
  }

  function _initializeDomainSeparator(bytes memory permitDomainName) internal {
    DOMAIN_SEPARATOR = EIP712Lib.domainSeparator(permitDomainName);
  }

  // solhint-disable-next-line func-name-mixedcase
  function EIP712_REVISION() external pure returns (bytes memory) {
    return EIP712Lib.EIP712_REVISION;
  }

  struct RequestedPolicy {
    bytes32 cid;
    address requestedBy;
  }

  mapping(address => RequestedPolicy) private _requestedPolicies;
  mapping(address => ApprovedPolicy) private _approvedPolicies;

  event ApplicationSubmitted(address indexed insured, bytes32 indexed requestCid);

  function submitApplication(bytes32 cid) external returns (address insured) {
    insured = _createInsured(msg.sender, address(0));
    _submitApplication(insured, cid);
  }

  function submitApplication(bytes32 cid, address impl) external returns (address insured) {
    Value.require(impl != address(0));
    insured = _createInsured(msg.sender, impl);
    _submitApplication(insured, cid);
  }

  function _submitApplication(address insured, bytes32 cid) private {
    Value.require(cid != 0);
    _requestedPolicies[insured] = RequestedPolicy({cid: cid, requestedBy: msg.sender});
    emit ApplicationSubmitted(insured, cid);
  }

  function _createInsured(address requestedBy, address impl) private returns (address) {
    IProxyFactory pf = getProxyFactory();
    bytes memory callData = ProxyTypes.insuredInit(requestedBy);
    if (impl == address(0)) {
      return pf.createProxy(requestedBy, _insuredProxyType, callData);
    }
    return pf.createProxyWithImpl(requestedBy, _insuredProxyType, impl, callData);
  }

  function resubmitApplication(address insured, bytes32 cid) external {
    State.require(!hasApprovedApplication(insured));

    _submitApplication(insured, cid);
  }

  function hasApprovedApplication(address insured) public view returns (bool) {
    return insured == address(0) ? false : _approvedPolicies[insured].insured == insured;
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

  event ApplicationApproved(address indexed approver, address indexed insured, bytes32 indexed requestCid, ApprovedPolicy data);

  function approveApplication(ApprovedPolicy calldata data) external aclHas(AccessFlags.UNDERWRITER_POLICY) {
    _approveApplication(msg.sender, data);
  }

  function approveApplicationByPermit(
    address approver,
    ApprovedPolicy calldata data,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    uint256 currentNonce = ++_nonces[data.insured];
    bytes32 value = keccak256(abi.encode(data));
    EIP712Lib.verifyPermit(approver, data.insured, value, deadline, v, r, s, APPROVE_APPL_TYPEHASH, DOMAIN_SEPARATOR, currentNonce);

    _approveApplication(approver, data);
  }

  function _approveApplication(address approver, ApprovedPolicy calldata data) private {
    Access.require(hasAnyAcl(approver, AccessFlags.UNDERWRITER_POLICY));
    Value.require(data.insured != address(0));
    Value.require(data.requestCid != 0);
    Value.require(!data.applied);
    State.require(!hasApprovedApplication(data.insured));
    _approvedPolicies[data.insured] = data;
    emit ApplicationApproved(approver, data.insured, data.requestCid, data);
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
    uint256 payoutRatio;
  }

  mapping(address => RequestedClaim[]) private _requestedClaims;
  mapping(address => ApprovedClaim) private _approvedClaims;

  event ClaimSubmitted(address indexed insured, bytes32 indexed cid, uint256 payoutRatio);

  function submitClaim(
    address insured,
    bytes32 cid,
    uint256 payoutRatio
  ) external returns (uint256) {
    Value.require(cid != 0);
    Value.require(insured != address(0));
    State.require(!hasApprovedClaim(insured));
    Access.require(IClaimAccessValidator(insured).canClaimInsurance(msg.sender));

    RequestedClaim[] storage claims = _requestedClaims[insured];
    claims.push(RequestedClaim({cid: cid, requestedBy: msg.sender, payoutRatio: payoutRatio}));

    emit ClaimSubmitted(insured, cid, payoutRatio);

    return claims.length;
  }

  function hasApprovedClaim(address insured) public view returns (bool) {
    return _approvedClaims[insured].requestCid != 0;
  }

  function getApprovedClaim(address insured) public view returns (ApprovedClaim memory) {
    State.require(hasApprovedClaim(insured));
    return _approvedClaims[insured];
  }

  event ClaimApproved(address indexed approver, address indexed insured, bytes32 indexed requestCid, ApprovedClaim data);

  function approveClaim(address insured, ApprovedClaim calldata data) external aclHas(AccessFlags.UNDERWRITER_CLAIM) {
    _approveClaim(msg.sender, insured, data);
  }

  function approveClaimByPermit(
    address approver,
    address insured,
    ApprovedClaim calldata data,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    uint256 currentNonce = ++_nonces[insured];
    bytes32 value = keccak256(abi.encode(data));
    EIP712Lib.verifyPermit(approver, insured, value, deadline, v, r, s, APPROVE_CLAIM_TYPEHASH, DOMAIN_SEPARATOR, currentNonce);

    _approveClaim(approver, insured, data);
  }

  function _approveClaim(
    address approver,
    address insured,
    ApprovedClaim calldata data
  ) private {
    Access.require(hasAnyAcl(approver, AccessFlags.UNDERWRITER_CLAIM));
    Value.require(insured != address(0));
    Value.require(data.requestCid != 0);
    State.require(!hasApprovedClaim(insured));
    _approvedClaims[insured] = data;
    emit ClaimApproved(approver, insured, data.requestCid, data);
  }

  event ClaimApplied(address indexed insured, bytes32 indexed requestCid, ApprovedClaim data);

  function applyApprovedClaim(address insured) external returns (ApprovedClaim memory data) {
    data = getApprovedClaim(insured);
    emit ClaimApplied(insured, data.requestCid, data);
  }
}
