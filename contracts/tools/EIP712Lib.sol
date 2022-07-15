// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './Errors.sol';

library EIP712Lib {
  bytes internal constant EIP712_REVISION = '1';
  bytes32 internal constant EIP712_DOMAIN = keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');

  function chainId() internal view returns (uint256 id) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      id := chainid()
    }
  }

  function domainSeparator(bytes memory permitDomainName) internal view returns (bytes32) {
    return keccak256(abi.encode(EIP712_DOMAIN, keccak256(permitDomainName), keccak256(EIP712_REVISION), chainId(), address(this)));
  }

  /**
   * @param owner the owner of the funds
   * @param spender the spender
   * @param value the amount
   * @param deadline the deadline timestamp, type(uint256).max for no deadline
   * @param v signature param
   * @param s signature param
   * @param r signature param
   */
  function verifyPermit(
    address owner,
    address spender,
    bytes32 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes32 typeHash,
    bytes32 domainSep,
    uint256 nonce
  ) internal view {
    verifyCustomPermit(owner, abi.encode(typeHash, owner, spender, value, nonce, deadline), deadline, v, r, s, domainSep);
  }

  function verifyCustomPermit(
    address owner,
    bytes memory params,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes32 domainSep
  ) internal view {
    Value.require(owner != address(0));
    if (block.timestamp > deadline) {
      revert Errors.ExpiredPermit();
    }

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSep, keccak256(params)));

    if (owner != ecrecover(digest, v, r, s)) {
      revert Errors.WrongPermitSignature();
    }
  }
}
