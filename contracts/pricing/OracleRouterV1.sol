// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import './OracleRouterBase.sol';

contract OracleRouterV1 is VersionedInitializable, OracleRouterBase {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl, address quote) AccessHelper(acl) OracleRouterBase(quote) {}

  function initializePriceOracle() public initializer(CONTRACT_REVISION) {
    // _initializeDomainSeparator();
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
