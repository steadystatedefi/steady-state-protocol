// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../interfaces/IProxyFactory.sol';
import '../funds/Collateralized.sol';
import '../access/AccessHelper.sol';
import './interfaces/IApprovalCatalog.sol';
import './interfaces/IGovernorAccessBitmask.sol';

abstract contract GovernedHelper is AccessHelper, Collateralized {
  constructor(IAccessController acl, address collateral_) AccessHelper(acl) Collateralized(collateral_) {}

  function _onlyGovernorOrAcl(uint256 flags, bool canOverride) internal view {
    address g = governorAccount();
    if (g != msg.sender) {
      (uint256 mask, uint256 overrides) = internalQueryGovernorAcl(g, msg.sender, flags);
      if (mask == 0) {
        overrides = canOverride ? flags & ~overrides : flags;
        Access.require(overrides != 0 && hasAnyAcl(msg.sender, overrides));
      }
    }
  }

  function _onlyGovernor() private view {
    Access.require(governorAccount() == msg.sender);
  }

  function internalQueryGovernorAcl(
    address g,
    address account,
    uint256 flags
  ) internal view virtual returns (uint256 mask, uint256 overrides) {
    return g == address(0) ? (0, 0) : IGovernorAccessBitmask(g).governorQueryAccessControlMask(account, flags);
  }

  function _onlyAclOrGovernor(uint256 flags) private view {
    _onlyGovernorOrAcl(flags, false);
  }

  modifier onlyAclOrGovernor(uint256 flags) {
    _onlyAclOrGovernor(flags);
    _;
  }

  function _onlyGovernorOr(uint256 flags) private view {
    _onlyGovernorOrAcl(flags, true);
  }

  modifier onlyGovernorOr(uint256 flags) {
    _onlyGovernorOr(flags);
    _;
  }

  modifier onlyGovernor() {
    _onlyGovernor();
    _;
  }

  function _onlySelf() private view {
    Access.require(msg.sender == address(this));
  }

  modifier onlySelf() {
    _onlySelf();
    _;
  }

  function governorAccount() internal view virtual returns (address);

  function approvalCatalog() internal view returns (IApprovalCatalog) {
    return IApprovalCatalog(getAclAddress(AccessFlags.APPROVAL_CATALOG));
  }
}
