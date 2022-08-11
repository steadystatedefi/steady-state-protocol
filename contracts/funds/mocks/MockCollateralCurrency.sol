// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../CollateralCurrency.sol';

contract MockCollateralCurrency is CollateralCurrency {
  address private _owner;

  constructor(string memory name_, string memory symbol_) CollateralCurrency(IAccessController(address(0)), name_, symbol_) {
    _owner = msg.sender;
  }

  function hasAnyAcl(address subject, uint256) internal view override returns (bool) {
    return subject == _owner;
  }

  function hasAllAcl(address subject, uint256) internal view override returns (bool) {
    return subject == _owner;
  }

  function isAdmin(address addr) internal view override returns (bool) {
    return addr == _owner;
  }
}
