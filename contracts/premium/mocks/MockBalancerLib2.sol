// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../BalancerLib2.sol';

contract MockBalancerLib2 {
  using BalancerLib2 for BalancerLib2.AssetBalancer;

  BalancerLib2.AssetBalancer private _poolBalance;

  function getTotalBalance() external view returns (Balances.RateAcc memory) {
    return _poolBalance.totalBalance;
  }

  function setGlobals(uint32 spFactor, uint160 spConst) external {
    _poolBalance.spFactor = spFactor;
    _poolBalance.spConst = spConst;
  }

  function setTotalBalance(uint128 accum, uint96 rate) external {
    _poolBalance.totalBalance = Balances.RateAcc(accum, rate, uint32(block.timestamp));
  }

  function setConfig(
    address asset,
    uint144 price,
    uint64 w,
    uint32 n,
    uint16 flags,
    uint160 spConst
  ) external {
    _poolBalance.configs[asset] = BalancerLib2.AssetConfig(price, w, n, flags, spConst);
  }

  function setBalance(
    address asset,
    uint128 accum,
    uint96 rate
  ) external {
    _poolBalance.balances[asset] = BalancerLib2.AssetBalance(accum, rate, uint32(block.timestamp));
  }

  function getBalance(address asset) external view returns (BalancerLib2.AssetBalance memory) {
    return _poolBalance.balances[asset];
  }

  event TokenSwapped(uint256 amount, uint256 fee);

  uint256 private _replenishDelta;
  uint256 private _exchangeRate = WadRayMath.WAD;

  function setReplenishDelta(uint256 delta) external {
    _replenishDelta = delta;
  }

  function setExchangeRate(uint16 pctRate) external {
    _exchangeRate = PercentageMath.percentMul(WadRayMath.WAD, pctRate);
  }

  function _replenishFn(BalancerLib2.ReplenishParams memory, uint256 v)
    private
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    v += _replenishDelta;
    return (WadRayMath.wadDiv(v, _exchangeRate), v, v);
  }

  function swapToken(
    address token,
    uint256 value,
    uint256 minAmount
  ) external returns (uint256 amount, uint256 fee) {
    (amount, fee) = _poolBalance.swapAsset(
      BalancerLib2.ReplenishParams({actuary: address(0), source: address(0), token: token, replenishFn: _replenishFn}),
      value,
      minAmount
    );
    emit TokenSwapped(amount, fee);
  }
}
