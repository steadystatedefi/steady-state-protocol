// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IPriceRouter.sol';

interface IManagedPriceRouter is IPriceRouter {
  function getPriceSource(address asset) external view returns (PriceSource memory result);

  function getPriceSources(address[] calldata assets) external view returns (PriceSource[] memory result);

  function setPriceSources(address[] calldata assets, PriceSource[] calldata prices) external;

  function setStaticPrices(address[] calldata assets, uint256[] calldata prices) external;

  function setPriceSourceRange(
    address asset,
    uint256 targetPrice,
    uint16 tolerancePct
  ) external;

  function getPriceSourceRange(address asset) external view returns (uint256 targetPrice, uint16 tolerancePct);

  function attachSource(address asset, bool attach) external;

  function registerSourceGroup(
    address account,
    uint256 mask,
    bool register
  ) external;

  function resetSourceGroup() external;

  function resetSourceGroupByAdmin(uint256 mask) external;
}

enum PriceFeedType {
  StaticValue,
  ChainLinkV3,
  UniSwapV2Pair
}

struct PriceSource {
  PriceFeedType feedType;
  address feedContract;
  uint256 feedConstValue;
  uint8 decimals;
  address crossPrice;
}
