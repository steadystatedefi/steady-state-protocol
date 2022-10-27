// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev A minimal required interface for a Uniswap V2 pair usable as a price source.
interface IPriceFeedUniswapV2 {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function getReserves()
    external
    view
    returns (
      uint112 reserve0,
      uint112 reserve1,
      uint32 blockTimestampLast
    );
  // function price0CumulativeLast() external view returns (uint);
  // function price1CumulativeLast() external view returns (uint);
  // function kLast() external view returns (uint);
}
