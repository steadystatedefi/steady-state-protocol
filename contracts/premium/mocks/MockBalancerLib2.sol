// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../BalancerLib2.sol';

contract MockBalancerLib2 {
  using BalancerLib2 for BalancerLib2.PoolBalances;

  BalancerLib2.PoolBalances private _poolBalance;

  function getTotalBalance() external view returns (Balances.RateAcc memory) {
    return _poolBalance.totalBalance;
  }

  function setTotalBalance(uint128 accum, uint96 rate) external {
    _poolBalance.totalBalance = Balances.RateAcc(accum, rate, uint32(block.timestamp));
  }

  function setConfig(
    address asset,
    uint160 price,
    uint64 w,
    uint32 n
  ) external {
    _poolBalance.configs[asset] = BalancerLib2.AssetConfig(price, w, n);
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

  function swapToken(
    address token,
    uint256 value,
    uint256 minAmount
  ) external returns (uint256 amount, uint256 fee) {
    (amount, fee) = _poolBalance.swapToken(token, value, minAmount);
    emit TokenSwapped(amount, fee);
  }
}
