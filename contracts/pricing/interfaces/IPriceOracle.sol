// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IFallbackPriceOracle.sol';

interface IPriceOracle is IFallbackPriceOracle {
  function getAssetPrices(address[] calldata asset) external view returns (uint256[] memory);

  function pullAssetPrice(address asset, uint256 fuseMask) external returns (uint256);
}
