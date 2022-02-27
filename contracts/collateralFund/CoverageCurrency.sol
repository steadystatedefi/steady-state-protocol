// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../tools/tokens/ERC20Base.sol';
import '../tools/tokens/ERC20MintableBase.sol';

//contract CoverageCurrency is ERC20BalancelessBase, ERC20MintableBase {
contract CoverageCurrency is ERC20Base {
  constructor() ERC20Base('Coverage Currency', 'CC', 18) {}

  //Should this also be in "CollateralFundBalances" and change it to "CollateralFundTokens"?
}
