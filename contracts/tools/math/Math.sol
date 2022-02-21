// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Math {
  function sqrt(uint256 y) internal pure returns (uint256 z) {
    if (y > 3) {
      z = y;
      uint256 x = (y >> 1) + 1;
      while (x < z) {
        z = x;
        x = (y / x + x) >> 1;
      }
    } else if (y != 0) {
      z = 1;
    }
  }
}
