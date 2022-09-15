// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/tokens/ERC20Base.sol';
import '../../tools/math/WadRayMath.sol';
import '../../interfaces/IYieldStakeAsset.sol';
import '../../interfaces/ICollateralStakeManager.sol';
import '../Collateralized.sol';

contract MockInsurerForYield is IYieldStakeAsset, Collateralized, ERC20Base {
  using WadRayMath for uint256;

  uint256 private _collateralSupplyFactor;

  constructor(address cc) Collateralized(cc) ERC20Base('Insured', '$IT0', 18) {
    _collateralSupplyFactor = WadRayMath.WAD;
  }

  function setCollateralSupplyFactor(uint256 collateralSupplyFactor) external {
    _collateralSupplyFactor = collateralSupplyFactor;
  }

  function totalSupply() public view override(ERC20Base, IYieldStakeAsset) returns (uint256) {
    return super.totalSupply();
  }

  function collateralSupply() public view override returns (uint256) {
    return super.totalSupply().wadMul(_collateralSupplyFactor);
  }

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }

  function callSyncByAsset() external {
    ICollateralStakeManager m = ICollateralStakeManager(IManagedCollateralCurrency(collateral()).borrowManager());
    if (address(m) != address(0)) {
      m.syncByStakeAsset(totalSupply(), collateralSupply());
    }
  }
}
