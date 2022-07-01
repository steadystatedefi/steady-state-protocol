// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import './interfaces/IAccessController.sol';
import './AccessHelper.sol';
import './AccessFlags.sol';

// solhint-disable func-name-mixedcase
abstract contract MarketAccessBitmask {
  using AccessHelper for IAccessController;
  IAccessController internal _remoteAcl;

  constructor(IAccessController remoteAcl) {
    _remoteAcl = remoteAcl;
  }

  function _getRemoteAcl(address addr) internal view returns (uint256) {
    return _remoteAcl.getAcl(addr);
  }

  function hasRemoteAcl() internal view returns (bool) {
    return address(_remoteAcl) != address(0);
  }

  function acl_hasAnyOf(address subject, uint256 flags) internal view returns (bool) {
    return _remoteAcl.hasAnyOf(subject, flags);
  }

  // modifier aclHas(uint256 flags) virtual {
  //   _remoteAcl.requireAnyOf(msg.sender, flags, Errors.TXT_ACCESS_RESTRICTED);
  //   _;
  // }

  // modifier aclAnyOf(uint256 flags) {
  //   _remoteAcl.requireAnyOf(msg.sender, flags, Errors.TXT_ACCESS_RESTRICTED);
  //   _;
  // }

  // modifier onlyEmergencyAdmin() {
  //   _remoteAcl.requireAnyOf(msg.sender, AccessFlags.EMERGENCY_ADMIN, Errors.CALLER_NOT_EMERGENCY_ADMIN);
  //   _;
  // }

  // function _onlySweepAdmin() internal view virtual {
  //   _remoteAcl.requireAnyOf(msg.sender, AccessFlags.SWEEP_ADMIN, Errors.CALLER_NOT_SWEEP_ADMIN);
  // }

  // modifier onlySweepAdmin() {
  //   _onlySweepAdmin();
  //   _;
  // }
}
