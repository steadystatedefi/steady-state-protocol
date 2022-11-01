// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../AccessController.sol';

contract MockAccessController is AccessController {
  uint8 private constant ANY_ROLE_BLOCKED = 1;
  uint8 private constant ANY_ROLE_ENABLED = 2;
  uint8 private _anyRoleMode;

  constructor(uint256 moreMultilets) AccessController(moreMultilets) {}

  function setAnyRoleMode(bool blockOrEnable) external onlyOwnerOrAdmin {
    if (blockOrEnable) {
      State.require(_anyRoleMode != ANY_ROLE_BLOCKED);
      _anyRoleMode = ANY_ROLE_ENABLED;
      emit AnyRoleModeEnabled();
    } else if (_anyRoleMode != ANY_ROLE_BLOCKED) {
      _anyRoleMode = ANY_ROLE_BLOCKED;
      emit AnyRoleModeBlocked();
    }
  }

  function grantAnyRoles(address addr, uint256 flags) external onlyOwnerOrAdmin returns (uint256) {
    State.require(_anyRoleMode == ANY_ROLE_ENABLED);
    return _grantMultiRoles(addr, flags, false);
  }

  function ensureNoSingletons() internal override {
    if (_anyRoleMode != ANY_ROLE_ENABLED) {
      super.ensureNoSingletons();
    }
  }
}
