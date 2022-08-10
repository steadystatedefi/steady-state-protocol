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
  bytes32 private immutable _insuredProxyType;

  constructor(IAccessController acl, bytes32 insuredProxyType) AccessHelper(acl) {
    _insuredProxyType = insuredProxyType;
    _initializeDomainSeparator();
  }

  mapping(address => uint256) private _nonces;

  /// @dev returns nonce, to comply with eip-2612
  function nonces(address addr) external view returns (uint256) {
    return _nonces[addr];
  }

  function _initializeDomainSeparator() internal {
    DOMAIN_SEPARATOR = EIP712Lib.domainSeparator('ApprovalCatalog');
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

  function submitApplication(bytes32 cid, address collateral) external returns (address insured) {
    Value.require(collateral != address(0));
    insured = _createInsured(msg.sender, address(0), collateral);
    _submitApplication(insured, cid);
  }

  function submitApplicationWithImpl(bytes32 cid, address impl) external returns (address insured) {
    Value.require(impl != address(0));
    insured = _createInsured(msg.sender, impl, address(0));
    _submitApplication(insured, cid);
  }

  function _submitApplication(address insured, bytes32 cid) private {
    Value.require(cid != 0);
    _requestedPolicies[insured] = RequestedPolicy({cid: cid, requestedBy: msg.sender});
    emit ApplicationSubmitted(insured, cid);
  }

  function _createInsured(
    address requestedBy,
    address impl,
    address collateral
  ) private returns (address) {
    IProxyFactory pf = getProxyFactory();
    bytes memory callData = ProxyTypes.insuredInit(requestedBy);
    if (impl == address(0)) {
      return pf.createProxy(requestedBy, _insuredProxyType, collateral, callData);
    }
    return pf.createProxyWithImpl(requestedBy, _insuredProxyType, impl, callData);
  }

  function resubmitApplication(address insured, bytes32 cid) external {
    State.require(!hasApprovedApplication(insured));

    _submitApplication(insured, cid);
  }

  function hasApprovedApplication(address insured) public view returns (bool) {
    return insured != address(0) && _approvedPolicies[insured].insured == insured;
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

  bytes32 public constant APPROVE_APPL_TYPEHASH =
    keccak256(
      // solhint-disable-next-line max-line-length
      'approveApplicationByPermit(address approver,T1 data,uint256 nonce,uint256 expiry)T1(bytes32 requestCid,bytes32 approvalCid,address insured,uint16 riskLevel,uint80 basePremiumRate,string policyName,string policySymbol,address premiumToken,uint96 minPrepayValue,uint32 rollingAdvanceWindow,uint32 expiresAt,bool applied)'
    );
  bytes32 private constant APPROVE_APPL_DATA_TYPEHASH =
    keccak256(
      // solhint-disable-next-line max-line-length
      'T1(bytes32 requestCid,bytes32 approvalCid,address insured,uint16 riskLevel,uint80 basePremiumRate,string policyName,string policySymbol,address premiumToken,uint96 minPrepayValue,uint32 rollingAdvanceWindow,uint32 expiresAt,bool applied)'
    );

  function approveApplicationByPermit(
    address approver,
    ApprovedPolicy calldata data,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    uint256 nonce = _nonces[data.insured]++;
    EIP712Lib.verifyCustomPermit(
      approver,
      abi.encode(APPROVE_APPL_TYPEHASH, approver, _encodeApplicationPermit(data), nonce, deadline),
      deadline,
      v,
      r,
      s,
      DOMAIN_SEPARATOR
    );

    _approveApplication(approver, data);
  }

  function _encodeApplicationPermit(ApprovedPolicy calldata data) private pure returns (bytes32) {
    // NB! There is no problem for usual compilation, BUT during coverage
    // And this chunked encoding is a workaround for "stack too deep" during coverage.

    bytes memory prefix = abi.encode(
      APPROVE_APPL_DATA_TYPEHASH,
      data.requestCid,
      data.approvalCid,
      data.insured,
      data.riskLevel,
      data.basePremiumRate
    );

    return
      keccak256(
        abi.encodePacked(
          prefix,
          _encodeString(data.policyName),
          _encodeString(data.policySymbol),
          abi.encode(data.premiumToken, data.minPrepayValue, data.rollingAdvanceWindow, data.expiresAt, data.applied)
        )
      );
  }

  function _encodeString(string calldata data) private pure returns (bytes32) {
    return keccak256(abi.encodePacked(data));
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

  bytes32 public constant APPROVE_CLAIM_TYPEHASH =
    keccak256(
      // solhint-disable-next-line max-line-length
      'approveClaimByPermit(address approver,address insured,T1 data,uint256 nonce,uint256 expiry)T1(bytes32 requestCid,bytes32 approvalCid,uint16 payoutRatio,uint32 since)'
    );
  bytes32 private constant APPROVE_CLAIM_DATA_TYPEHASH = keccak256('T1(bytes32 requestCid,bytes32 approvalCid,uint16 payoutRatio,uint32 since)');

  function _encodeClaimPermit(ApprovedClaim calldata data) private pure returns (bytes32) {
    return keccak256(abi.encode(APPROVE_CLAIM_DATA_TYPEHASH, data));
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
    uint256 nonce = _nonces[insured]++;
    EIP712Lib.verifyCustomPermit(
      approver,
      abi.encode(APPROVE_CLAIM_TYPEHASH, approver, insured, _encodeClaimPermit(data), nonce, deadline),
      deadline,
      v,
      r,
      s,
      DOMAIN_SEPARATOR
    );
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

  function cancelLastPermit(address insured)
    external
    aclHasAny(AccessFlags.UNDERWRITER_CLAIM | AccessFlags.UNDERWRITER_POLICY | AccessFlags.INSURED_ADMIN)
  {
    Value.require(insured != address(0));
    _nonces[insured]++;
  }
}
