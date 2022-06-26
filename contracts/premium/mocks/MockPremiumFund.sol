// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../PremiumFund.sol';

contract MockPremiumFund is PremiumFund {
  mapping(address => uint256) private _prices;

  constructor(address collateral_) PremiumFund(collateral_) {}

  modifier onlyAdmin() override {
    _;
  }

  function setConfig(
    address actuary,
    address asset,
    uint152 price,
    uint64 w,
    uint32 n,
    uint16 flags,
    uint160 spConst
  ) external {
    _balancers[actuary].configs[asset] = BalancerLib2.AssetConfig(price, w, n, flags, spConst);
  }

  function setDefaultConfig(
    address actuary,
    uint152 price,
    uint64 w,
    uint32 n,
    uint16 flags,
    uint160 spConst
  ) external {
    _configs[actuary].defaultConfig = BalancerLib2.AssetConfig(price, w, n, flags, spConst);
  }

  function balancesOf(address actuary, address source) external view returns (SourceBalance memory) {
    return _configs[actuary].sourceBalances[source];
  }

  function getConifg(address actuary, address asset) external view returns (BalancerLib2.AssetConfig memory) {
    return _balancers[actuary].configs[asset];
  }

  function setPrice(address token, uint256 price) external {
    _prices[token] = price;
  }

  function priceOf(address token) public view override returns (uint256) {
    return _prices[token];
  }

  /*
  function registerPremiumActuary(address actuary, bool register) external override onlyAdmin {
    PremiumFund.registerPremiumActuary(actuary,register);
  }
  */
}
