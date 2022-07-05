// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../interfaces/IProxyFactory.sol';
import '../insurance/Collateralized.sol';
import '../access/AccessHelper.sol';

abstract contract GovernedHelper is AccessHelper, Collateralized {
  IAccessController private immutable _remoteAcl;

  address private _governor;
  bool internal _governorIsContract;

  constructor(IAccessController acl, address collateral_) Collateralized(collateral_) {
    _remoteAcl = acl;
  }

  function remoteAcl() internal view override returns (IAccessController) {
    return _remoteAcl;
  }

  function _onlyGovernorOr(uint256 flags) internal view {
    require(_isAllowed(flags) || hasAnyAcl(msg.sender, flags));
  }

  function _onlyGovernor() private view {
    require(_isAllowed(0));
  }

  function _isAllowed(uint256 flags) private view returns (bool) {
    return _governor == msg.sender || isAllowedByGovernor(msg.sender, flags);
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
    require(msg.sender == address(this));
  }

  modifier onlySelf() {
    _onlySelf();
    _;
  }

  function _setGovernor(address addr) internal {
    emit GovernorUpdated(_governor = addr);
  }

  function governorAccount() internal view returns (address) {
    return _governor;
  }

  event GovernorUpdated(address);
}
