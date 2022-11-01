// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import '../governance/interfaces/IInsurerGovernor.sol';
import '../governance/GovernedHelper.sol';
import './InsurerJoinBase.sol';

abstract contract WeightedPoolAccessControl is GovernedHelper, InsurerJoinBase {
  using PercentageMath for uint256;

  address private _governor;
  bool private _governorIsContract;

  function _onlyActiveInsured(address insurer) internal view {
    Access.require(internalGetStatus(insurer) == MemberStatus.Accepted);
  }

  function _onlyInsured(address insurer) private view {
    Access.require(internalGetStatus(insurer) > MemberStatus.Unknown);
  }

  modifier onlyActiveInsured() {
    _onlyActiveInsured(msg.sender);
    _;
  }

  modifier onlyInsured() {
    _onlyInsured(msg.sender);
    _;
  }

  function _onlyActiveInsuredOrOps(address insured) private view {
    if (insured != msg.sender) {
      _onlyGovernorOrAcl(AccessFlags.INSURER_OPS, false);
    }
    _onlyActiveInsured(insured);
  }

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
    IInsurerGovernor g = governorContract();
    if (address(g) == address(0)) {
      IApprovalCatalog c = approvalCatalog();
      if (address(c) == address(0)) {
        return payoutRatio;
      }

      if (!enforcedCancel || c.hasApprovedClaim(insured)) {
        IApprovalCatalog.ApprovedClaim memory info = c.applyApprovedClaim(insured);

        Access.require(enforcedCancel || info.since <= block.timestamp);
        approvedPayoutRatio = WadRayMath.RAY.percentMul(info.payoutRatio);
      }
      // else approvedPayoutRatio = 0 (for enfoced calls without an approved claim)
    } else if (!enforcedCancel || payoutRatio > 0) {
      approvedPayoutRatio = g.verifyPayoutRatio(insured, payoutRatio);
    }

    if (payoutRatio < approvedPayoutRatio) {
      approvedPayoutRatio = payoutRatio;
    }
  }
}
