// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IERC20WithPermit.sol';
import './EIP712Base.sol';

abstract contract ERC20PermitBase is IERC20WithPermit, EIP712Base {
  bytes32 public constant PERMIT_TYPEHASH = keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  constructor() {
    _initializeDomainSeparator();
  }

  function _initializeDomainSeparator() internal {
    super._initializeDomainSeparator(_getPermitDomainName());
  }

  /**
   * @dev implements the permit function as for https://github.com/ethereum/EIPs/blob/8a34d644aacf0f9f8f00815307fd7dd5da07655f/EIPS/eip-2612.md
   * @param owner the owner of the funds
   * @param spender the spender
   * @param value the amount
   * @param deadline the deadline timestamp, type(uint256).max for no deadline
   * @param v signature param
   * @param s signature param
   * @param r signature param
   */

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external override {
    Value.require(owner != address(0));
    internalPermit(owner, spender, value, deadline, v, r, s, PERMIT_TYPEHASH);
    _approveByPermit(owner, spender, value);
  }

  function _approveByPermit(
    address owner,
    address spender,
    uint256 value
  ) internal virtual;

  function _getPermitDomainName() internal view virtual returns (bytes memory);
}
