// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../CollateralFundBase.sol';

contract MockCollateralFund is CollateralFundBase {
  mapping(address => uint256) private _prices;

  constructor(address collateral_) {
    _initialize(collateral_);
  }

  function setSpecialApprovals(address operator, uint256 access) external {
    internalSetSpecialApprovals(operator, access);
  }

  function addAsset(
    address token,
    uint64 priceTarget,
    uint16 priceTolerance,
    address trusted
  ) external {
    internalAddAsset(token, priceTarget, priceTolerance, trusted);
    _prices[token] = priceTarget;
  }

  function removeAsset(address token) external {
    internalRemoveAsset(token);
  }

  function internalPriceOf(address token) internal view override returns (uint256) {
    return _prices[token];
  }

  function setPriceOf(address token, uint256 price) external {
    _prices[token] = price;
  }

  function setTrusted(address token, address trusted) external {
    internalSetTrusted(token, trusted);
  }

  function setPaused(address token, bool paused) external {
    internalSetFlags(token, paused ? 0 : type(uint8).max);
  }
}
