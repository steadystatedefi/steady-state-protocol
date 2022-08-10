// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './AccessFlags.sol';
import './AccessControllerBase.sol';

contract AccessController is AccessControllerBase {
  constructor(uint256 moreMultilets)
    AccessControllerBase(AccessFlags.SINGLETS, AccessFlags.ROLES | AccessFlags.ROLES_EXT | moreMultilets, AccessFlags.PROTECTED_SINGLETS)
  {}
}
