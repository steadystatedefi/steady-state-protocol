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

  /// @dev Submits an application for a new insurance policy.
  /// @dev The application form must be uploaded to IPFS.
  /// @dev This method will deploy a new proxy with a default implementation of type _insuredProxyType.
  /// @param cid is an addressable hash from IPFS for the application form.
  /// @param collateral is an address of collateral currency for the insurance policy.
  /// @return insured is a contract to represent the insurance policy.
  function submitApplication(bytes32 cid, address collateral) external returns (address insured) {
    Value.require(collateral != address(0));
    insured = _createInsured(msg.sender, address(0), collateral);
    _submitApplication(insured, cid);
  }

  /// @dev Submits an application for a new insurance policy with a custom implementation.
  /// @dev The application form must be uploaded to IPFS.
  /// @dev This method will deploy a new proxy with the given implementation.
  /// @param cid is an addressable hash from IPFS for the application form.
  /// @param impl is an implementation for a new insured. The implementation must be authentic and has a collateral currency as context.
  /// @return insured is a contract to represent the insurance policy.
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

  /// @dev Submits an update for an application. The application must not be approved.
  /// @dev The updated application form must be uploaded to IPFS.
  /// @dev This method will update an application for the given insured.
  /// @param insured is a draft insurance policy to be updated. Returned by submitApplication().
  /// @param cid is an addressable hash from IPFS for the updated application form.
  function resubmitApplication(address insured, bytes32 cid) external {
    State.require(!hasApprovedApplication(insured));

    _submitApplication(insured, cid);
  }

  /// @inheritdoc IApprovalCatalog
  function hasApprovedApplication(address insured) public view returns (bool) {
    return insured != address(0) && _approvedPolicies[insured].insured == insured;
  }

  /// @inheritdoc IApprovalCatalog
  function getApprovedApplication(address insured) external view returns (ApprovedPolicy memory) {
    State.require(hasApprovedApplication(insured));
    return _approvedPolicies[insured];
  }

  event ApplicationApplied(address indexed insured, bytes32 indexed requestCid);

  /// @inheritdoc IApprovalCatalog
  function applyApprovedApplication() external returns (ApprovedPolicy memory data) {
    address insured = msg.sender;
    State.require(hasApprovedApplication(insured));
    data = _approvedPolicies[insured];
    _approvedPolicies[insured].applied = true;

    emit ApplicationApplied(insured, data.requestCid);
  }

  /// @inheritdoc IApprovalCatalog
  function getAppliedApplicationForInsurer(address insured) external view returns (bool valid, ApprovedPolicyForInsurer memory data) {
    ApprovedPolicy storage policy = _approvedPolicies[insured];
    if (policy.insured == insured && policy.applied) {
      data = ApprovedPolicyForInsurer({riskLevel: policy.riskLevel, basePremiumRate: policy.basePremiumRate, premiumToken: policy.premiumToken});
      valid = true;
    }
  }

  event ApplicationApproved(address indexed approver, address indexed insured, bytes32 indexed requestCid, ApprovedPolicy data);

  /// @dev Uploads an approved application. Only a grantee of the UNDERWRITER_POLICY role can call.
  /// @dev The application is identified by data.insured.
  /// @param data contains required parameters assigned/approved by the underwriter.
  function approveApplication(ApprovedPolicy calldata data) external {
    _onlyUnderwriterOfPolicy(msg.sender);

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

  /// @dev Approves an apprication with EIP712 permit issued offline.
  /// @param approver is an address of the underwiter, a signer of this permit.
  /// @param data of the approval.
  /// @param deadline is an expiry of the EIP712 permit.
  /// @param v, r, s - are signature params of the EIP712 permit.
  function approveApplicationByPermit(
    address approver,
    ApprovedPolicy calldata data,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    _onlyUnderwriterOfPolicy(approver);

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

  function _onlyUnderwriterOfPolicy(address approver) private view {
    Access.require(hasAnyAcl(approver, AccessFlags.UNDERWRITER_POLICY));
  }

  function _approveApplication(address approver, ApprovedPolicy calldata data) private {
    Value.require(data.insured != address(0));
    Value.require(data.requestCid != 0);
    Value.require(!data.applied);
    State.require(!hasApprovedApplication(data.insured));
    _approvedPolicies[data.insured] = data;
    emit ApplicationApproved(approver, data.insured, data.requestCid, data);
  }

  event ApplicationDeclined(address indexed insured, bytes32 indexed cid, string reason);

  /// @dev Declines an application. The application must not be applied yet, otherwise this call reverts.
  /// @param insured is to identify an application
  /// @param cid is to identify a version of an application. It prevents racing with resubmitApplication()
  /// @return true when the application was declined, and false when the insured is unknown or cid doesnt match.
  function declineApplication(
    address insured,
    bytes32 cid,
    string calldata reason
  ) external returns (bool) {
    _onlyUnderwriterOfPolicy(msg.sender);

    Value.require(insured != address(0));
    ApprovedPolicy storage data = _approvedPolicies[insured];
    if (data.insured != address(0)) {
      Sanity.require(data.insured == insured);
      if (data.requestCid == cid) {
        // decline of the previously approved one is only possible when is was not applied
        State.require(!data.applied);
        delete _approvedPolicies[insured];

        emit ApplicationDeclined(insured, cid, reason);
        return true;
      }
    }
    return false;
  }

  struct RequestedClaim {
    bytes32 cid; // supporting documents
    address requestedBy;
    uint256 payoutValue;
  }

  mapping(address => RequestedClaim[]) private _requestedClaims;
  mapping(address => ApprovedClaim) private _approvedClaims;

  event ClaimSubmitted(address indexed insured, bytes32 indexed cid, uint256 payoutValue, uint256 claimNo);

  /// @dev Reqisters a request to claim to get an insurance payment.
  /// @dev Caller must be accepted by the insured as claimer. See IClaimAccessValidator.canClaimInsurance()
  /// @param insured policy of the claim
  /// @param cid of a document/form supporting the claim
  /// @param payoutValue requested from the policy
  /// @return a sequential number of the claim for this insured
  function submitClaim(
    address insured,
    bytes32 cid,
    uint256 payoutValue
  ) external returns (uint256) {
    Access.require(insured != address(0) && IClaimAccessValidator(insured).canClaimInsurance(msg.sender));
    Value.require(cid != 0);
    State.require(!hasApprovedClaim(insured));

    RequestedClaim[] storage claims = _requestedClaims[insured];
    claims.push(RequestedClaim({cid: cid, requestedBy: msg.sender, payoutValue: payoutValue}));

    emit ClaimSubmitted(insured, cid, payoutValue, claims.length);

    return claims.length;
  }

  /// @inheritdoc IApprovalCatalog
  function hasApprovedClaim(address insured) public view returns (bool) {
    return _approvedClaims[insured].requestCid != 0;
  }

  /// @inheritdoc IApprovalCatalog
  function getApprovedClaim(address insured) public view returns (ApprovedClaim memory) {
    State.require(hasApprovedClaim(insured));
    return _approvedClaims[insured];
  }

  event ClaimApproved(address indexed approver, address indexed insured, bytes32 indexed requestCid, ApprovedClaim data);

  /// @dev Approves a claim payout from the given `insured` policy. A payout can be approved without submitClaim().
  /// @param insured policy of the claim.
  /// @param data of the approval.
  function approveClaim(address insured, ApprovedClaim calldata data) external {
    _onlyUnderwriterClaim(msg.sender);
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

  /// @dev Approves a claim payout with EIP712 permit issued offline.
  /// @param approver is an address of the underwiter, a signer of this permit.
  /// @param insured policy of the claim.
  /// @param data of the approval.
  /// @param deadline is an expiry of the EIP712 permit.
  /// @param v, r, s - are signature params of the EIP712 permit.
  function approveClaimByPermit(
    address approver,
    address insured,
    ApprovedClaim calldata data,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    _onlyUnderwriterClaim(approver);
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

  function _onlyUnderwriterClaim(address approver) private view {
    Access.require(hasAnyAcl(approver, AccessFlags.UNDERWRITER_CLAIM));
  }

  function _approveClaim(
    address approver,
    address insured,
    ApprovedClaim calldata data
  ) private {
    Value.require(insured != address(0));
    Value.require(data.requestCid != 0);
    State.require(!hasApprovedClaim(insured));
    _approvedClaims[insured] = data;
    emit ClaimApproved(approver, insured, data.requestCid, data);
  }

  event ClaimApplied(address indexed insured, bytes32 indexed requestCid, ApprovedClaim data);

  /// @inheritdoc IApprovalCatalog
  function applyApprovedClaim(address insured) external returns (ApprovedClaim memory data) {
    data = getApprovedClaim(insured);
    emit ClaimApplied(insured, data.requestCid, data);
  }

  /// @dev Cancels any EIP712 permit (for either an application or a payout) currently issued for the `insured`.
  /// @dev Caller must have any of these roles: UNDERWRITER_CLAIM, UNDERWRITER_POLICY, INSURED_ADMIN
  function cancelLastPermit(address insured)
    external
    aclHasAny(AccessFlags.UNDERWRITER_CLAIM | AccessFlags.UNDERWRITER_POLICY | AccessFlags.INSURED_ADMIN)
  {
    Value.require(insured != address(0));
    _nonces[insured]++;
  }
}
