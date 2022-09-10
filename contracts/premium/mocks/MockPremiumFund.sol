// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../PremiumFundBase.sol';

contract MockPremiumFund is PremiumFundBase {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => uint256) private _prices;

  constructor(address collateral_) PremiumFundBase(IAccessController(address(0)), collateral_) {}

  function isAdmin(address) internal pure override returns (bool) {
    return true;
  }

  function hasAnyAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function hasAllAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function setAutoReplenish(address actuary, address asset) external {
    _balancers[actuary].configs[asset].flags |= BalancerLib2.BF_AUTO_REPLENISH;
  }

  function balancesOf(address actuary, address source) external view returns (SourceBalance memory) {
    return _configs[actuary].sourceBalances[source];
  }

  function balancerBalanceOf(address actuary, address token) external view returns (BalancerLib2.AssetBalance memory) {
    return _balancers[actuary].balances[token];
  }

  function balancerTotals(address actuary) external view returns (Balances.RateAcc memory) {
    return _balancers[actuary].totalBalance;
  }

  function setPrice(address token, uint256 price) external {
    _prices[token] = price;
  }

  function internalPriceOf(address token) internal view override returns (uint256) {
    if (token == collateral()) {
      return WadRayMath.WAD;
    }
    return _prices[token];
  }

  /*
  function registerPremiumActuary(address actuary, bool register) external override onlyAdmin {
    PremiumFundBase.registerPremiumActuary(actuary,register);
  }
  */
}
