// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../interfaces/IProxyFactory.sol';
import '../funds/Collateralized.sol';
import '../access/AccessHelper.sol';
import './interfaces/IApprovalCatalog.sol';

abstract contract GovernedHelper is AccessHelper, Collateralized {
  constructor(IAccessController acl, address collateral_) AccessHelper(acl) Collateralized(collateral_) {}

  function _onlyGovernorOr(uint256 flags) internal view {
    Access.require(_isAllowed(flags) || hasAnyAcl(msg.sender, flags));
  }

  function _onlyGovernor() private view {
    Access.require(governorAccount() == msg.sender);
  }

  function _isAllowed(uint256 flags) private view returns (bool) {
    return governorAccount() == msg.sender || isAllowedByGovernor(msg.sender, flags);
  }

  function isAllowedByGovernor(address account, uint256 flags) internal view virtual returns (bool) {}

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
