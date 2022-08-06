// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/IYieldDistributorInit.sol';
import './YieldDistributorBase.sol';

contract YieldDistributorV1 is IYieldDistributorInit, VersionedInitializable, YieldDistributorBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address collateral_) YieldDistributorBase(acl, collateral_) {}

  function initializeYieldDistributor() public override initializer(CONTRACT_REVISION) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
