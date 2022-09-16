// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC20MintableBalancelessBase.sol';
import '../tools/tokens/IERC1363.sol';
import '../access/AccessHelper.sol';
import './InvestmentCurrencyBase.sol';

abstract contract YieldingCurrencyBase is InvestmentCurrencyBase {
  using Math for uint256;
  using WadRayMath for uint256;

  mapping(address => uint256) private _accumulatedYield;
  uint104 private _yieldRateAccum;

  // uint104 private _prevRateAccum;
  // uint32 private _lastYieldAt;

  function updateNonInvestSupply(uint256 decrement, uint256 increment) internal override {
    super.updateNonInvestSupply(decrement, increment);
  }

  function internalGetCurrentYieldBase() internal view override returns (uint104) {
    return _yieldRateAccum;
  }

  function internalAddAccountYield(
    address account,
    uint256 balance,
    uint256 baseBefore,
    uint256 baseAfter
  ) internal override {
    _accumulatedYield[account] += balance.wadMul(baseAfter - baseBefore);
  }

  function internalAddYield(uint256 amount) internal {
    (, uint256 totalInvested) = totalAndInvestedSupply();
    amount = amount.wadDiv(totalInvested);

    uint104 prevYieldRateAccum = _yieldRateAccum;
    uint104 yieldRateAccum = prevYieldRateAccum + uint104(amount);
    Arithmetic.require(yieldRateAccum >= amount);
    _yieldRateAccum = yieldRateAccum;

    internalUpdateYieldRate(prevYieldRateAccum, yieldRateAccum);
  }

  function internalUpdateYieldRate(uint256 prevYieldRateAccum, uint256 yieldRateAccum) internal virtual;

  function expectedYieldRate() internal view returns (uint256, uint32) {}

  function internalPullYield(address account) internal returns (uint256) {}
}
