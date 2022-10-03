// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ERC20TransferBase.sol';

abstract contract ERC20MintableBase is ERC20TransferBase {
  /** @dev Creates `amount` tokens and assigns them to `account`, increasing
   * the total supply.
   *
   * Emits a {Transfer} event with `from` set to the zero address.
   *
   * Requirements
   *
   * - `to` cannot be the zero address.
   */
  function _mint(address account, uint256 amount) internal virtual {
    require(account != address(0), 'ERC20: mint to the zero address');

    _beforeTokenTransfer(address(0), account, amount);

    updateTotalSupply(0, amount);
    incrementBalance(account, amount);

    emit Transfer(address(0), account, amount);
  }

  function _mintAndTransfer(
    address account,
    address recipient,
    uint256 amount
  ) internal virtual {
    require(account != address(0), 'ERC20: mint to the zero address');
    require(recipient != address(0), 'ERC20: transfer to the zero address');

    _beforeTokenTransfer(address(0), account, amount);
    _beforeTokenTransfer(account, recipient, amount);

    updateTotalSupply(0, amount);
    incrementBalance(recipient, amount);

    emit Transfer(address(0), account, amount);
    emit Transfer(account, recipient, amount);
  }

  /**
   * @dev Destroys `amount` tokens from `account`, reducing the
   * total supply.
   *
   * Emits a {Transfer} event with `to` set to the zero address.
   *
   * Requirements
   *
   * - `account` cannot be the zero address.
   * - `account` must have at least `amount` tokens.
   */
  function _burn(address account, uint256 amount) internal virtual {
    require(account != address(0), 'ERC20: burn from the zero address');

    _beforeTokenTransfer(account, address(0), amount);

    updateTotalSupply(amount, 0);
    decrementBalance(account, amount);

    emit Transfer(account, address(0), amount);
  }

  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal virtual override {
    decrementBalance(sender, amount);
    incrementBalance(recipient, amount);
  }

  function incrementBalance(address account, uint256 amount) internal virtual;

  function decrementBalance(address account, uint256 amount) internal virtual;

  function updateTotalSupply(uint256 decrement, uint256 increment) internal virtual;
}
