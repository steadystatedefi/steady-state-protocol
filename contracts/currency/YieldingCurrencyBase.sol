// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC20MintableBalancelessBase.sol';
import '../tools/tokens/IERC1363.sol';
import '../access/AccessHelper.sol';
import './InvestmentCurrencyBase.sol';
import './YieldingBase.sol';

abstract contract YieldingCurrencyBase is AccessHelper, InvestmentCurrencyBase, YieldingBase {
  using Math for uint256;
  using WadRayMath for uint256;
  using InvestAccount for InvestAccount.Balance;

  function totalAndManagedSupply() public view override(InvestmentCurrencyBase, YieldingBase) returns (uint256, uint256) {
    return InvestmentCurrencyBase.totalAndManagedSupply();
  }

  function internalGetBalance(address account) internal view override(InvestmentCurrencyBase, YieldingBase) returns (InvestAccount.Balance) {
    return InvestmentCurrencyBase.internalGetBalance(account);
  }

  function internalBeforeManagedBalanceUpdate(address account, InvestAccount.Balance accBalance)
    internal
    override(InvestmentCurrencyBase, YieldingBase)
  {
    YieldingBase.internalBeforeManagedBalanceUpdate(account, accBalance);
  }

  function incrementBalance(address account, uint256 amount) internal override {
    super.incrementBalance(account, amount);

    if (account == address(this) && amount != 0) {
      // this is yield mint
      internalAddYield(amount);
    }
  }
}
