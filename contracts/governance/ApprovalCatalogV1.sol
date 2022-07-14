// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import './ApprovalCatalog.sol';
import './ProxyTypes.sol';

contract ApprovalCatalogV1 is VersionedInitializable, ApprovalCatalog {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl) ApprovalCatalog(acl, ProxyTypes.INSURED_POOL) {}

  function initializeApprovalCatalog() public initializer(CONTRACT_REVISION) {
    _initializeDomainSeparator();
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
