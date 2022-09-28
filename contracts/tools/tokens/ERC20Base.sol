// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ERC20DetailsBase.sol';
import './ERC20AllowanceBase.sol';
import './ERC20BalanceBase.sol';
import './ERC20MintableBase.sol';

abstract contract ERC20Base is ERC20DetailsBase, ERC20AllowanceBase, ERC20BalanceBase, ERC20MintableBase {
  uint256 private _totalSupply;

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) ERC20DetailsBase(name_, symbol_, decimals_) {}

  function _approveTransferFrom(address owner, uint256 amount) internal override(ERC20AllowanceBase, ERC20TransferBase) {
    ERC20AllowanceBase._approveTransferFrom(owner, amount);
  }

  function incrementBalance(address account, uint256 amount) internal override(ERC20BalanceBase, ERC20MintableBase) {
    ERC20BalanceBase.incrementBalance(account, amount);
  }

  function decrementBalance(address account, uint256 amount) internal override(ERC20BalanceBase, ERC20MintableBase) {
    ERC20BalanceBase.decrementBalance(account, amount);
  }

  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
  }

  function updateTotalSupply(uint256 decrement, uint256 increment) internal override {
    _totalSupply = (_totalSupply - decrement) + increment;
  }
}
