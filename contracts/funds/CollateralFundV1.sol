// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/ICollateralFundInit.sol';
import './CollateralFundBase.sol';

contract CollateralFundV1 is VersionedInitializable, ICollateralFundInit, CollateralFundBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address collateral_) CollateralFundBase(acl, collateral_) {}

  function initializeCollateralFund() public override initializer(CONTRACT_REVISION) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }

  function internalPriceOf(address) internal pure override returns (uint256) {
    // revert Errors.NotImplemented(); // TODO
  }
}
