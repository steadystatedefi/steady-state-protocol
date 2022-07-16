// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import './PriceOracleBase.sol';

contract PriceOracleV1 is VersionedInitializable, PriceOracleBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl) AccessHelper(acl) {}

  function initializePriceOracle() public initializer(CONTRACT_REVISION) {
    // _initializeDomainSeparator();
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
