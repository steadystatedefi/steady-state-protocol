// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../CollateralFundBase.sol';

contract MockCollateralFund is CollateralFundBase {
  mapping(address => uint256) private _prices;

  constructor(address collateral_) CollateralFundBase(IAccessController(address(0)), collateral_) {}

  function internalAddAsset(
    address token,
    uint64 priceTarget,
    uint16 priceTolerance,
    address trusted
  ) internal override {
    super.internalAddAsset(token, priceTarget, priceTolerance, trusted);
    _prices[token] = priceTarget;
  }

  function internalPriceOf(address token) internal view override returns (uint256) {
    return _prices[token];
  }

  function setPriceOf(address token, uint256 price) external {
    _prices[token] = price;
  }

  function hasAnyAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function hasAllAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }
}
