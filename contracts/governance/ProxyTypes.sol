// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../access/interfaces/IAccessController.sol';

library ProxyTypes {
  bytes32 internal constant INSURED = 'INSURED';

  function insuredInit(IAccessController acl, address owner) internal pure returns (bytes memory) {
    return abi.encodeWithSignature('initialize(address,address)', acl, owner);
  }
}
