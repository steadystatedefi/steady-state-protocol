// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../YieldDistributorBase.sol';

contract MockYieldDistributor is YieldDistributorBase {
  mapping(address => uint256) private _prices;

  constructor(address accesscontroller_, address collateral_) YieldDistributorBase(IAccessController(accesscontroller_), collateral_) {}

  function hasAnyAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function hasAllAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }
}
