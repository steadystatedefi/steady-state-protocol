// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IPriceRouter.sol';

/// @dev Additional functions to confugure the price oracle/ router.
/// @dev A contract (e.g. a collateral fund) can be assined with zero or more source groups and will be added assets to these groups.
/// @dev Each source group is identified by a bit in a bitmask.
/// @dev When an asset will get a price outside of a defined safe range, then it will trip / blow a fuse for all groups it was added into.
/// @dev When a source group remains 'blown', relevant collateral funds will stop its operations.
interface IManagedPriceRouter is IPriceRouter {
  /// @return information about a price source for the given `asset`.
  function getPriceSource(address asset) external view returns (PriceSource memory);

  /// @return information about price sources for the given `assets`.
  function getPriceSources(address[] calldata assets) external view returns (PriceSource[] memory);

  /// @dev Sets price sources for the given `assets`. See PriceSource.
  function setPriceSources(address[] calldata assets, PriceSource[] calldata prices) external;

  /// @dev Sets static prices for the given `assets`.
  /// @dev When a source was already set, it keeps the settings, hence the value must be with the same decimals as the source,
  /// @dev When a source was not set, then it will be configuread as 18 decimals and no cross-pricing.
  function setStaticPrices(address[] calldata assets, uint256[] calldata prices) external;

  /// @dev Sets safe price ranges for the assets. Can ONLY be applied to assests with non-static prices.
  /// @param assets to be configured. Assets must be already added.
  /// @param targetPrices for each asset (middle of a safe price range), 18 decimal values, rounded to 9. Zero price means no range check.
  /// @param tolerancePcts are percentages of allowed deviation for each asset, 4 decimals, rounded to 2.5.
  function setSafePriceRanges(
    address[] calldata assets,
    uint256[] calldata targetPrices,
    uint16[] calldata tolerancePcts
  ) external;

  /// @dev Returns safe price range set for the `asset`. Zero target price means no range check.
  function getPriceSourceRange(address asset) external view returns (uint256 targetPrice, uint16 tolerancePct);

  /// @dev Adds/removes assets to/from source guard group(s) of the caller. Ignored for a caller without groups.
  /// @param asset to be added into or removed from source guard group(s) of the caller.
  /// @param attach is true to add the asset, otherwise - to remove it.
  function attachSource(address asset, bool attach) external;

  /// @dev Resets source guard group(s) of the caller tripped by a price out of safe range. Ignored for a caller without groups.
  function resetSourceGroup() external;

  /// @dev Assigns source guard group(s) to the given `account`. Only for PRICE_ROUTER_ADMIN.
  /// @param account to be configured.
  /// @param mask of source groups.
  function configureSourceGroup(address account, uint256 mask) external;

  /// @dev Resets source guard group(s) defined by the `mask`. Only for PRICE_ROUTER_ADMIN.
  function resetSourceGroupByAdmin(uint256 mask) external;
}

enum PriceFeedType {
  StaticValue,
  ChainLinkV3,
  UniSwapV2Pair
}

struct PriceSource {
  /// @dev type of the price source
  PriceFeedType feedType;
  /// @dev address of a price source (must be zero for PriceFeedType.StaticValue)
  address feedContract;
  /// @dev value of a price source (must be zero for non PriceFeedType.StaticValue)
  uint256 feedConstValue;
  /// @dev decimals of a value from the price source. E.g. the source has 9 decimals, then the value will be multipled by 1e9 to get 18 decimals.
  uint8 decimals;
  /// @dev when non zero, the resulting price is multiplied by the price of the asset given here
  address crossPrice;
}
