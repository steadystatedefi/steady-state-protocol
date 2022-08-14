// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import './PriceGuardOracleBase.sol';

contract OracleRouterV1 is VersionedInitializable, PriceGuardOracleBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address quote) PriceGuardOracleBase(acl, quote) {}

  function initializePriceOracle() public initializer(CONTRACT_REVISION) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
