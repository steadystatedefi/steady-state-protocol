// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IERC1363.sol';

abstract contract ERC1363ReceiverBase is IERC1363Receiver {
  function onTransferReceived(
    address operator,
    address from,
    uint256 value,
    bytes calldata data
  ) external override returns (bytes4) {
    internalReceiveTransfer(operator, from, value, data);
    return this.onTransferReceived.selector;
  }

  function internalReceiveTransfer(
    address operator,
    address from,
    uint256 value,
    bytes calldata data
  ) internal virtual;
}
