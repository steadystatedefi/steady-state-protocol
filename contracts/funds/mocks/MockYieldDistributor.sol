// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../YieldDistributorBase.sol';

contract MockYieldDistributor is YieldDistributorBase {
  mapping(address => uint256) private _prices;

  constructor(address collateral_) YieldDistributorBase(IAccessController(address(0)), collateral_) {}

  function hasAnyAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function hasAllAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function internalPullYieldFrom(uint8 sourceType, address) internal pure override returns (uint256) {
    if (sourceType != 2) {
      revert Errors.NotImplemented();
    }
    return 0;
  }
}
