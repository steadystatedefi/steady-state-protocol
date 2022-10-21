// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Basic / read only price oracle.
interface IFallbackPriceOracle {
  /// @return an asset for the price quotes (all price vaules are nominated in it)
  function getQuoteAsset() external view returns (address);

  /// @return a price of the given `asset` valued in the quote asset. Must revert when the price is not available or is zero.
  function getAssetPrice(address asset) external view returns (uint256);
}
