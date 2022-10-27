// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library CallData {
  /// @return sig - a selector (first 4 bytes) from the calldata provided
  function getSelector(bytes calldata data) internal pure returns (bytes4 sig) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      calldatacopy(0, data.offset, 4)
      sig := mload(0)
    }
  }
}
