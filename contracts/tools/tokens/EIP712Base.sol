// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../EIP712Lib.sol';

abstract contract EIP712Base {
  // solhint-disable-next-line var-name-mixedcase
  bytes32 public DOMAIN_SEPARATOR;

  mapping(address => uint256) private _nonces;

  /// @dev returns nonce, to comply with eip-2612
  function nonces(address addr) external view returns (uint256) {
    return _nonces[addr];
  }

  // solhint-disable-next-line func-name-mixedcase
  function EIP712_REVISION() external pure returns (bytes memory) {
    return EIP712Lib.EIP712_REVISION;
  }

  function _initializeDomainSeparator(bytes memory permitDomainName) internal {
    DOMAIN_SEPARATOR = EIP712Lib.domainSeparator(permitDomainName);
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

  function internalPermit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    bytes32 typeHash
  ) internal {
    uint256 currentValidNonce = _nonces[owner]++;
    EIP712Lib.verifyPermit(owner, spender, bytes32(value), deadline, v, r, s, typeHash, DOMAIN_SEPARATOR, currentValidNonce);
  }
}
