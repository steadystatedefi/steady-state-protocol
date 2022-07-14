// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../interfaces/IProxyFactory.sol';
import '../funds/Collateralized.sol';
import '../access/AccessHelper.sol';
import '../governance/interfaces/IApprovalCatalog.sol';

contract FrontHelper is AccessHelper {
  constructor(IAccessController acl) AccessHelper(acl) {}
}
