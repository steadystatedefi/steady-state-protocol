// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IManagedAccessController.sol';

contract MockCaller {
  //uint256 public lastTempRole;

  /*
  function setLastTempRole() external {
    lastTempRole = IManagedAccessController(msg.sender).queryAccessControlMask(address(this), 0);
  }
  */

  function checkRoleDirect(uint256 flags) external {
    require(IManagedAccessController(msg.sender).queryAccessControlMask(address(this), flags) == flags, 'Incorrect roles');
  }

  function checkRoleIndirect(IManagedAccessController controller, uint256 flags) external {
    require(controller.queryAccessControlMask(msg.sender, flags) == flags, 'Incorrect roles');
  }
}
