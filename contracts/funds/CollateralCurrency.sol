// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './CallbackBase.sol';

contract CollateralCurrency is CallbackBase {
  // Ownable

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) ERC20Base(name_, symbol_, decimals_) {}
}
