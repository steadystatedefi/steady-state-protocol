// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IFallbackPriceOracle {
  function getQuoteAsset() external view returns (address);

  function getAssetPrice(address asset) external view returns (uint256);
}
