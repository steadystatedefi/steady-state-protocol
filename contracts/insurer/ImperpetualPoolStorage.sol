// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import './WeightedPoolStorage.sol';

abstract contract ImperpetualPoolStorage is WeightedPoolStorage, ERC20BalancelessBase, IExcessHandler {
  using WadRayMath for uint256;

  uint256 internal _burntCoverage;
  uint256 internal _claimedCoverage;
  uint256 private _totalSupply;

  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  function totalSupplyValue() public view returns (uint256 v) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    v = (coverage.totalPremium + _excessCoverage) - _burntCoverage;
    v += (coverage.totalCovered + coverage.pendingCovered) - _claimedCoverage;
  }

  function exchangeRate() public view virtual returns (uint256 v) {
    if ((v = _totalSupply) > 0) {
      return totalSupplyValue() / v;
    }
  }
}
