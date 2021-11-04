// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IERC20Details.sol';

library ERC1363 {
  // 0x88a7ca5c === bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))
  bytes4 internal constant RECEIVER = type(IERC1363Receiver).interfaceId;

  /* 0xb0202a11 ===
   *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
   *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
   *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
   *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
   *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
   *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
   */
  bytes4 internal constant TOKEN = 0xb0202a11;
}

interface IERC1363Receiver {
  /**
   * @notice Handle the receipt of ERC1363 tokens
   * @dev Any ERC1363 smart contract calls this function on the recipient
   * after a `transfer` or a `transferFrom`. This function MAY throw to revert and reject the
   * transfer. Return of other than the magic value MUST result in the
   * transaction being reverted.
   * Note: the token contract address is always the message sender.
   * @param operator address The address which called `transferAndCall` or `transferFromAndCall` function
   * @param from address The address which are token transferred from
   * @param value uint256 The amount of tokens transferred
   * @param data bytes Additional data with no specified format
   * @return `bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))`
   *  unless throwing
   */
  function onTransferReceived(
    address operator,
    address from,
    uint256 value,
    bytes memory data
  ) external returns (bytes4);
}
