// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Holds the USDX tokens for a particular protocol. This vault will contain the rules about
///     the underlying USDX backing a protocol, NOT the rules regarding the ERC20
interface IVirtualReserve {
  /// @dev deposit will be called by the owning pool, transferring the USDX tokens. Does not keep track of owners
  function deposit(address owner, uint256 amount) external;

  //TODO: Access control
  /// @dev Certain depistors can deposit
  function setAllowedCollateralizationRatio(address depositor, uint256 ratio) external;
}
