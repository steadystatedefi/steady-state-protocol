// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Arrays {
  /// @dev truncates the array `a` down to length `n`
  function truncateUint256(uint256[] memory a, uint256 n) internal pure {
    require(n <= a.length);
    // solhint-disable-next-line no-inline-assembly
    assembly {
      mstore(a, n)
    }
  }
}
