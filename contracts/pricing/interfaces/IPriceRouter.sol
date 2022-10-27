// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IFallbackPriceOracle.sol';

interface IPriceRouter is IFallbackPriceOracle {
  /// @return prices of the given `assets` valued in the quote asset. Must revert when any of requisted prices is not available or is zero.
  function getAssetPrices(address[] calldata asset) external view returns (uint256[] memory);

  /// @dev Returns a guarded price, a price within safety limits.
  /// @dev Must revert when the price is not available.
  /// @param asset to be priced.
  /// @param fuseMask is a mask that defines guarded group(s). Will return zero price when any member of guarded group(s) is unsafe.
  /// @return a price of the given `asset` valued in the quote asset or zero when the price is not safe/usable.
  function pullAssetPrice(address asset, uint256 fuseMask) external returns (uint256);
}
