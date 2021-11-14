// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../interfaces/IInsurancePool.sol';

abstract contract InsurancePoolBase is IInsurancePool {
  address private _collateral;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function collateral() public view override returns (address) {
    return _collateral;
  }

  function _initialize(address collateral_) internal {
    _collateral = collateral_;
  }

  modifier onlyCollateralFund() {
    require(msg.sender == _collateral);
    _;
  }

  function transferCollateral(address to, uint256 amount) internal {
    // collateral is a trusted token, hence we do not use safeTransfer here
    require(IERC20(collateral()).transfer(to, amount));
  }
}
