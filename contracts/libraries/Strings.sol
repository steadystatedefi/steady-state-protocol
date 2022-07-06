// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Strings {
  function trimRight(bytes memory s) internal pure returns (bytes memory) {
    uint256 i = s.length;
    for (; i > 0; i--) {
      if (s[i - 1] > 0x20) {
        break;
      }
    }
    // solhint-disable-next-line no-inline-assembly
    assembly {
      mstore(s, i)
    }
    return s;
  }

  function trimRight(string memory s) internal pure returns (string memory) {
    return string(trimRight(bytes(s)));
  }

  function asString(bytes32 data) internal pure returns (string memory) {
    return string(trimRight(abi.encodePacked(data)));
  }
}
