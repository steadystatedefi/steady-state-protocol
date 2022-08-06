// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IPriceFeedUniswapV2.sol';

contract MockUniswapV2 is IPriceFeedUniswapV2 {
  address public token0;
  address public token1;

  uint112 private reserve0_;
  uint112 private reserve1_;

  constructor(address _token0, address _token1) {
    token0 = _token0;
    token1 = _token1;
  }

  function setReserves(uint112 _reserve0, uint112 _reserve1) external {
    reserve0_ = _reserve0;
    reserve1_ = _reserve1;
  }

  function getReserves()
    external
    view
    returns (
      uint112 reserve0,
      uint112 reserve1,
      uint32 blockTimestampLast
    )
  {
    return (reserve0_, reserve1_, 0);
  }
}
