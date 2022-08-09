// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/IInsuredPoolInit.sol';
import './InsuredPoolMonoRateBase.sol';

contract InsuredPoolV1 is VersionedInitializable, IInsuredPoolInit, InsuredPoolMonoRateBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address collateral_) InsuredPoolMonoRateBase(acl, collateral_) {}

  function initializeInsured(address governor) public override initializer(CONTRACT_REVISION) {
    internalSetGovernor(governor);
  }

  function getRevision() internal pure virtual override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
