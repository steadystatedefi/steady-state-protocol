// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Strings {
  /// @dev Trims bytes <=0x20 from the right
  function trimRight(bytes memory s) internal pure {
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
  }

  /// @dev Trims bytes <=0x20 from the right
  function trimRight(string memory s) internal pure {
    trimRight(bytes(s));
  }

  /// @return s string of representation `data` trimmmed from right for bytes <=0x20
  function asString(bytes32 data) internal pure returns (string memory s) {
    s = string(abi.encodePacked(data));
    trimRight(s);
  }
}
