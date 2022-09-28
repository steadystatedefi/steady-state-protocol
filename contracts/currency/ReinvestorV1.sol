// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/IReinvestorInit.sol';
import '../access/AccessHelper.sol';
import './ReinvestManagerBase.sol';

contract ReinvestorV1 is IReinvestorInit, VersionedInitializable, ReinvestManagerBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address collateral_) ReinvestManagerBase(acl, collateral_) {}

  function initializeReinvestor() public override initializer(CONTRACT_REVISION) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
