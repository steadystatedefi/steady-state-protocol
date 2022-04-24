// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library AddressExt {
  function addr(uint256 v) internal pure returns (address) {
    return address(uint160(v));
  }

  function ext(uint256 v) internal pure returns (uint96) {
    return uint96(v >> 160);
  }

  function setAddr(uint256 v, address a) internal pure returns (uint256) {
    return (v & ~uint256(type(uint160).max)) | uint160(a);
  }

  function setExt(uint256 v, uint96 e) internal pure returns (uint256) {
    return (v & type(uint160).max) | (uint256(e) << 160);
  }

  function newAddressExt(address a, uint96 e) internal pure returns (uint256) {
    return (uint256(e) << 160) | uint160(a);
  }
}
