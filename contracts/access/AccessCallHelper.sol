// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';

/// @dev A helper contract to process batch calls by the access controller
contract AccessCallHelper {
  address private immutable _owner;

  constructor(address owner) {
    Value.require(owner != address(0));
    // slither-disable-next-line missing-zero-check
    _owner = owner;
  }

  function doCall(address callAddr, bytes calldata callData) external returns (bytes memory result) {
    Access.require(msg.sender == _owner);
    return Address.functionCall(callAddr, callData);
  }
}
