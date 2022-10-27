// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/tokens/ERC1363ReceiverBase.sol';

contract MockERC1363Receiver is ERC1363ReceiverBase {
  address public lastOperator;
  address public lastFrom;
  uint256 public lastValue;
  bytes public lastData;

  function internalReceiveTransfer(
    address operator,
    address from,
    uint256 value,
    bytes calldata data
  ) internal override {
    lastOperator = operator;
    lastFrom = from;
    lastValue = value;
    lastData = data;
  }
}
