// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/IPremiumFundInit.sol';
import './PremiumFundBase.sol';

contract PremiumFundV1 is VersionedInitializable, IPremiumFundInit, PremiumFundBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address collateral_) PremiumFundBase(acl, collateral_) {}

  function initializePremiumFund() public override initializer(CONTRACT_REVISION) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
