// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/ICollateralFundInit.sol';
import './CollateralFundBase.sol';

contract CollateralFundV1 is VersionedInitializable, ICollateralFundInit, CollateralFundBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(
    IAccessController acl,
    address collateral_,
    uint256 sourceFuses
  ) CollateralFundBase(acl, collateral_, sourceFuses) {}

  function initializeCollateralFund() public override initializer(CONTRACT_REVISION) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
