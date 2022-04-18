// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20Base.sol';
import '../tools/tokens/IERC1363.sol';

abstract contract TokenDelegateBase is ERC20Base {
  uint256 internal constant FLAG_MINT = 1 << 1;
  uint256 internal constant FLAG_BURN = 1 << 2;
  uint256 internal constant FLAG_TRANSFER_CALLBACK = 1 << 3;

  mapping(address => uint256) private _flags;

  function _onlyWithAnyFlags(uint256 flags) private view {
    require(_flags[msg.sender] & flags == flags && flags != 0);
  }

  modifier onlyWithFlags(uint256 flags) {
    _onlyWithAnyFlags(flags);
    _;
  }

  function transferBalanceAndEmit(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    super.transferBalanceAndEmit(sender, recipient, amount);
    _notifyRecipient(sender, recipient, amount);
  }

  function _notifyRecipient(
    address sender,
    address recipient,
    uint256 amount
  ) private {
    if (msg.sender != recipient && _flags[recipient] & FLAG_TRANSFER_CALLBACK != 0) {
      IERC1363Receiver(recipient).onTransferReceived(msg.sender, sender, amount, '');
    }
  }

  function _mintAndTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    super._mintAndTransfer(sender, recipient, amount);
    _notifyRecipient(sender, recipient, amount);
  }

  function internalSetFlags(address account, uint256 flags) internal {
    require(account != address(0));
    _flags[account] |= flags;
  }

  function internalUnsetFlags(address account, uint256 flags) internal {
    require(account != address(0));
    _flags[account] &= ~flags;
  }

  function internalUnsetFlags(address account) internal {
    delete _flags[account];
  }
}
