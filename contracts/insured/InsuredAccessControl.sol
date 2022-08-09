// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../governance/interfaces/IInsuredGovernor.sol';
import '../governance/GovernedHelper.sol';
import '../pricing/PricingHelper.sol';

abstract contract InsuredAccessControl is GovernedHelper, PricingHelper {
  using PercentageMath for uint256;

  address private _governor;
  bool private _governorIsContract;

  constructor(IAccessController acl, address collateral_) GovernedHelper(acl, collateral_) PricingHelper(_getPricerByAcl(acl)) {}

  function remoteAcl() internal view override(AccessHelper, PricingHelper) returns (IAccessController pricer) {
    return AccessHelper.remoteAcl();
  }

  function internalSetTypedGovernor(IInsuredGovernor addr) internal {
    _governorIsContract = true;
    _setGovernor(address(addr));
  }

  function internalSetGovernor(address addr) internal virtual {
    // will also return false for EOA
    _governorIsContract = ERC165Checker.supportsInterface(addr, type(IInsuredGovernor).interfaceId);
    _setGovernor(addr);
  }

  function governorContract() internal view virtual returns (IInsuredGovernor) {
    return IInsuredGovernor(_governorIsContract ? governorAccount() : address(0));
  }

  function isAllowedByGovernor(address account, uint256 flags) internal view override returns (bool) {
    return IInsuredGovernor(governorAccount()).governerQueryAccessControlMask(account, flags) & flags != 0;
  }

  event GovernorUpdated(address);

  function _setGovernor(address addr) internal {
    emit GovernorUpdated(_governor = addr);
  }

  function governorAccount() internal view override returns (address) {
    return _governor;
  }

  // function internalVerifyPayoutRatio(address insured, uint256 payoutRatio) internal virtual returns (uint256 approvedPayoutRatio) {
  //   IInsuredGovernor jh = governorContract();
  //   if (address(jh) == address(0)) {
  //     IApprovalCatalog c = approvalCatalog();
  //     if (address(c) != address(0)) {
  //       IApprovalCatalog.ApprovedClaim memory info = c.applyApprovedClaim(insured);
  //       approvedPayoutRatio = WadRayMath.RAY.percentMul(info.payoutRatio);
  //       if (payoutRatio >= approvedPayoutRatio) {
  //         return approvedPayoutRatio;
  //       }
  //     }
  //     return payoutRatio;
  //   } else {
  //     return jh.verifyPayoutRatio(insured, payoutRatio);
  //   }
  // }
}
