// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';

contract PoolToken is ERC20PresetMinterPauser {
  constructor(string memory name, string memory symbol) ERC20PresetMinterPauser(name, symbol) {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

    //Pauser role should be held by both the claim validator (triggered when a claim is filed) an emergency contract (to be removed)
    _setupRole(PAUSER_ROLE, msg.sender);

    //Minter role should be held by the coverage pool that this token represents
    _setupRole(MINTER_ROLE, msg.sender);
  }
}
