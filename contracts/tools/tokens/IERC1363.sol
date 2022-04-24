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
  bytes4 internal constant TOKEN = type(IERC1363).interfaceId;

  function callReceiver(
    address receiver,
    address operator,
    address from,
    uint256 value,
    bytes memory data
  ) internal {
    require(IERC1363Receiver(receiver).onTransferReceived(operator, from, value, data) == IERC1363Receiver.onTransferReceived.selector);
  }
}

interface IERC1363 {
  /**
   * @notice Transfer tokens from `msg.sender` to another address and then call `onTransferReceived` on receiver
   * @param recipient address The address which you want to transfer to
   * @param amount uint256 The amount of tokens to be transferred
   * @return true unless throwing
   */
  function transferAndCall(address recipient, uint256 amount) external returns (bool);

  /**
   * @notice Transfer tokens from `msg.sender` to another address and then call `onTransferReceived` on receiver
   * @param recipient address The address which you want to transfer to
   * @param amount uint256 The amount of tokens to be transferred
   * @param data bytes Additional data with no specified format, sent in call to `recipient`
   * @return true unless throwing
   */
  function transferAndCall(
    address recipient,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);

  /**
   * @notice Transfer tokens from one address to another and then call `onTransferReceived` on receiver
   * @param sender address The address which you want to send tokens from
   * @param recipient address The address which you want to transfer to
   * @param amount uint256 The amount of tokens to be transferred
   * @return true unless throwing
   */
  function transferFromAndCall(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  /**
   * @notice Transfer tokens from one address to another and then call `onTransferReceived` on receiver
   * @param sender address The address which you want to send tokens from
   * @param recipient address The address which you want to transfer to
   * @param amount uint256 The amount of tokens to be transferred
   * @param data bytes Additional data with no specified format, sent in call to `recipient`
   * @return true unless throwing
   */
  function transferFromAndCall(
    address sender,
    address recipient,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);

  /**
   * @notice Approve the passed address to spend the specified amount of tokens on behalf of msg.sender
   * and then call `onApprovalReceived` on spender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param spender address The address which will spend the funds
   * @param amount uint256 The amount of tokens to be spent
   */
  function approveAndCall(address spender, uint256 amount) external returns (bool);

  /**
   * @notice Approve the passed address to spend the specified amount of tokens on behalf of msg.sender
   * and then call `onApprovalReceived` on spender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param spender address The address which will spend the funds
   * @param amount uint256 The amount of tokens to be spent
   * @param data bytes Additional data with no specified format, sent in call to `spender`
   */
  function approveAndCall(
    address spender,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);
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
