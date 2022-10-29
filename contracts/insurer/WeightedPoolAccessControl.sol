// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import '../governance/interfaces/IInsurerGovernor.sol';
import '../governance/GovernedHelper.sol';
import './InsurerJoinBase.sol';

/// @dev This template provides extends access control with a governor.
/// @dev The governor can be either EOA or a contract.
/// @dev Both will get access to protected functions, and a contract can also enable callbacks by declaring IInsurerGovernor support via ERC165.
abstract contract WeightedPoolAccessControl is GovernedHelper, InsurerJoinBase {
  using PercentageMath for uint256;

  address private _governor;
  bool private _governorIsContract;

  function _onlyActiveInsured(address insured) internal view {
    Access.require(internalGetStatus(insured) == MemberStatus.Accepted);
  }

  /// @dev Allows only a caller (insured) with MemberStatus.Accepted
  modifier onlyActiveInsured() {
    _onlyActiveInsured(msg.sender);
    _;
  }

  function _onlyActiveInsuredOrOps(address insured) private view {
    if (insured != msg.sender) {
      _onlyGovernorOrAcl(AccessFlags.INSURER_OPS, false);
    }
    _onlyActiveInsured(insured);
  }

  /// @dev Allows an insured with MemberStatus.Accepted, and a caller either the insured, or a governor, or an INSURER_OPS
  modifier onlyActiveInsuredOrOps(address insured) {
    _onlyActiveInsuredOrOps(insured);
    _;
  }

  function internalSetTypedGovernor(IInsurerGovernor addr) internal {
    _governorIsContract = true;
    _setGovernor(address(addr));
  }

  function internalSetGovernor(address addr) internal virtual {
    // will also return false for EOA
    _governorIsContract = ERC165Checker.supportsInterface(addr, type(IInsurerGovernor).interfaceId);
    _setGovernor(addr);
  }

  /// @return a typed/callable contract of a governor, otherwise zero.
  function governorContract() internal view virtual returns (IInsurerGovernor) {
    return IInsurerGovernor(_governorIsContract ? governorAccount() : address(0));
  }

  function internalQueryGovernorAcl(
    address g,
    address account,
    uint256 flags
  ) internal view override returns (uint256 mask, uint256 overrides) {
    return super.internalQueryGovernorAcl(_governorIsContract ? g : address(0), account, flags);
  }

  function internalInitiateJoin(address insured) internal override returns (MemberStatus) {
    // The insured must be approved by the governor (when is it a compatible contract) or must have an approved application in the ApprovalCatalog.
    IJoinHandler jh = governorContract();
    if (address(jh) == address(0)) {
      IApprovalCatalog c = approvalCatalog();
      Access.require(address(c) == address(0) || c.hasApprovedApplication(insured));
      return MemberStatus.Joining;
    } else {
      return jh.handleJoinRequest(insured);
    }
  }

  event GovernorUpdated(address);

  function _setGovernor(address addr) internal {
    emit GovernorUpdated(_governor = addr);
  }

  function governorAccount() internal view override returns (address) {
    return _governor;
  }

  function internalVerifyPayoutRatio(
    address insured,
    uint256 payoutRatio,
    bool enforcedCancel
  ) internal virtual returns (uint256 approvedPayoutRatio) {
    // The claim must be approved by the governor (when is it a compatible contract) or must have an approval in the ApprovalCatalog.
    // An enforced cancellation with zero payout skips the ApprovalCatalog check / the governor's callback.
    IInsurerGovernor g = governorContract();
    if (address(g) == address(0)) {
      IApprovalCatalog c = approvalCatalog();
      if (address(c) == address(0)) {
        return payoutRatio;
      }

      if (!enforcedCancel || payoutRatio != 0 || c.hasApprovedClaim(insured)) {
        IApprovalCatalog.ApprovedClaim memory info = c.applyApprovedClaim(insured);

        Access.require(enforcedCancel || info.since <= block.timestamp);
        approvedPayoutRatio = WadRayMath.RAY.percentMul(info.payoutRatio);
      }
      // else approvedPayoutRatio = 0 (for enfoced calls without an approved claim)
    } else if (!enforcedCancel || payoutRatio != 0) {
      // governor is not involved for enforced cancellations with zero payout
      approvedPayoutRatio = g.verifyPayoutRatio(insured, payoutRatio);
    }

    if (payoutRatio < approvedPayoutRatio) {
      approvedPayoutRatio = payoutRatio;
    }
  }
}
