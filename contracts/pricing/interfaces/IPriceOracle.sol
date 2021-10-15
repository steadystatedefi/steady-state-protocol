// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IFallbackPriceOracle.sol';

enum PriceSourceType {
  Chainlink,
  UniV2EthPair
}

interface IPriceOracle is IFallbackPriceOracle {
  // solhint-disable-next-line func-name-mixedcase
  function WETH() external view returns (address);

  function getAssetPrices(address[] calldata asset) external view returns (uint256[] memory);

  struct PriceSource {
    address source;
    uint224 staticPrice;
    PriceSourceType sourceType;
  }

  function getPriceSource(address asset) external view returns (PriceSource memory);

  function getPriceSources(address[] calldata asset) external view returns (PriceSource[] memory);
}
