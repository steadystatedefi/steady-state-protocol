// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20Base.sol';
import '../interfaces/ITokenDelegate.sol';

abstract contract CallbackBase is ERC20Base {
  mapping(address => ITokenDelegate) private _callbacks;

  function transferBalanceAndEmit(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    super.transferBalanceAndEmit(sender, recipient, amount);

    ITokenDelegate cb = _callbacks[recipient];
    if (address(cb) != address(0)) {
      cb.onTransferReceived(msg.sender, sender, amount, '');
    }
  }

  function internalSetCallabck(address recepient, address callback) internal {
    require(recepient != address(0));
    _callbacks[recepient] = ITokenDelegate(callback);
  }

  function delegatedAllownance(
    address owner,
    address spender,
    uint256 value
  ) internal override returns (bool) {
    ITokenDelegate cb = _callbacks[owner];
    return address(cb) != address(0) && cb.delegatedAllowance(spender) >= value;
  }
}
