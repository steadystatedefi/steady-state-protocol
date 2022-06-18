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
    uint152 price,
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
    _poolBalance.balances[asset] = Balances.RateAcc(accum, rate, uint32(block.timestamp));
  }

  function getBalance(address asset) external view returns (Balances.RateAcc memory) {
    return _poolBalance.balances[asset];
  }

  event TokenSwapped(uint256 amount, uint256 fee);

  function _replenishFn(
    BalancerLib2.AssetBalancer storage,
    address,
    uint256 v
  ) private pure returns (uint256 amount, uint256 value) {
    return (v, v);
  }

  function swapToken(
    address token,
    uint256 value,
    uint256 minAmount
  ) external returns (uint256 amount, uint256 fee) {
    (amount, fee) = _poolBalance.swapAsset(token, value, minAmount, 0, _replenishFn);
    emit TokenSwapped(amount, fee);
  }
}
