// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../ReinvestManagerBase.sol';

contract MockReinvestManager is ReinvestManagerBase {
  constructor(address collateral_) ReinvestManagerBase(IAccessController(address(0)), collateral_) {}

  function hasAnyAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function hasAllAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function isAdmin(address) internal pure override returns (bool) {
    return true;
  }
}
