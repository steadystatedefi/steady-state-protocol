// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../Strings.sol';

contract MockLibs {
  function testBytes32ToString(bytes32 v) public pure returns (string memory) {
    return Strings.asString(v);
  }
}
