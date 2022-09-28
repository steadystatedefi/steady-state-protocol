// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../Strings.sol';
import '../../tools/Errors.sol';
import '../../tools/math/Math.sol';
import '../../premium/BalancerLib2.sol';

import 'hardhat/console.sol';

contract MockLibs {
  function testBytes32ToString(bytes32 v) public pure returns (string memory) {
    return Strings.asString(v);
  }

  function testOverflowUint128(uint256 v) public pure returns (uint128) {
    return Math.asUint128(v);
  }

  /// @dev mutable method is required for the test to parse panics properly
  function testOverflowUint128Mutable(uint256 v) external {
    Math.asUint128(v);
    _mutable();
  }

  function _mutable() private returns (bool) {}

  function testOverflowBits(uint256 v, uint256 bits) public pure {
    Math.overflowBits(v, bits);
  }

  function testCalcConfigValue(
    uint144 price,
    uint64 w,
    uint32 n,
    uint16 flags
  ) public pure returns (CalcConfigValue) {
    return CalcConfig.newValue(price, w, n, flags);
  }
}
