// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './TokenDelegateBase.sol';
import '../tools/SafeOwnable.sol';

contract CollateralCurrency is SafeOwnable, TokenDelegateBase {
  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) ERC20Base(name_, symbol_, decimals_) {}

  function registerLiquidityProvider(address account) external onlyOwner {
    internalSetFlags(account, FLAG_MINT | FLAG_BURN);
  }

  function registerInsurer(address account) external onlyOwner {
    internalSetFlags(account, FLAG_TRANSFER_CALLBACK);
  }

  function unregister(address account) external {
    require(msg.sender == account || msg.sender == owner());
    internalUnsetFlags(account);
  }

  function mint(address account, uint256 amount) external onlyWithFlags(FLAG_MINT) {
    _mint(account, amount);
  }

  function mintAndTransfer(
    address onBehalf,
    address recepient,
    uint256 amount
  ) external onlyWithFlags(FLAG_MINT) {
    _mintAndTransfer(onBehalf, recepient, amount);
  }

  function burn(address account, uint256 amount) external onlyWithFlags(FLAG_BURN) {
    _burn(account, amount);
  }
}
