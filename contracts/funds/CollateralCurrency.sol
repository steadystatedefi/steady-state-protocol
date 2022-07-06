// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../access/AccessHelper.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import './TokenDelegateBase.sol';

contract CollateralCurrency is IManagedCollateralCurrency, AccessHelper, TokenDelegateBase {
  constructor(
    IAccessController acl,
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) AccessHelper(acl) ERC20Base(name_, symbol_, decimals_) {}

  function registerLiquidityProvider(address account) external aclHas(AccessFlags.LP_ADMIN) {
    internalSetFlags(account, FLAG_MINT | FLAG_BURN);
  }

  function registerInsurer(address account) external aclHas(AccessFlags.INSURER_ADMIN) {
    // TODO protect insurer from withdraw
    internalSetFlags(account, FLAG_TRANSFER_CALLBACK);
  }

  function unregister(address account) external {
    if (msg.sender != account) {
      Access.require(hasAnyAcl(msg.sender, internalGetFlags(account) == FLAG_TRANSFER_CALLBACK ? AccessFlags.INSURER_ADMIN : AccessFlags.LP_ADMIN));
    }
    internalUnsetFlags(account);
  }

  function mint(address account, uint256 amount) external override onlyWithFlags(FLAG_MINT) {
    _mint(account, amount);
  }

  function mintAndTransfer(
    address onBehalf,
    address recipient,
    uint256 mintAmount,
    uint256 balanceAmount
  ) external override onlyWithFlags(FLAG_MINT) {
    if (balanceAmount == 0) {
      _mintAndTransfer(onBehalf, recipient, mintAmount);
    } else {
      _mint(onBehalf, mintAmount);
      if (balanceAmount == type(uint256).max) {
        balanceAmount = balanceOf(onBehalf);
      } else {
        balanceAmount += mintAmount;
      }
      _transfer(onBehalf, recipient, balanceAmount);
    }
  }

  function burn(address account, uint256 amount) external override onlyWithFlags(FLAG_BURN) {
    _burn(account, amount);
  }
}
