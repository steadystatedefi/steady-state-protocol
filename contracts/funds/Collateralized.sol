// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../interfaces/ICollateralized.sol';

abstract contract Collateralized is ICollateralized {
  address private immutable _collateral;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function collateral() public view virtual override returns (address) {
    return _collateral;
  }

  function _onlyCollateralCurrency() private view {
    require(msg.sender == _collateral);
  }

  modifier onlyCollateralCurrency() {
    _onlyCollateralCurrency();
    _;
  }

  function transferCollateral(address recipient, uint256 amount) internal {
    // collateral is a trusted token, hence we do not use safeTransfer here
    require(IERC20(collateral()).transfer(recipient, amount));
  }

  function balanceOfCollateral(address account) internal view returns (uint256) {
    return IERC20(collateral()).balanceOf(account);
  }

  function transferCollateralFrom(
    address from,
    address recipient,
    uint256 amount
  ) internal {
    // collateral is a trusted token, hence we do not use safeTransfer here
    require(IERC20(collateral()).transferFrom(from, recipient, amount));
  }

  function transferAvailableCollateralFrom(
    address from,
    address recipient,
    uint256 maxAmount
  ) internal returns (uint256 amount) {
    IERC20 token = IERC20(collateral());
    amount = maxAmount;
    if (amount > (maxAmount = token.allowance(from, address(this)))) {
      if (maxAmount == 0) {
        return 0;
      }
      amount = maxAmount;
    }
    if (amount > (maxAmount = token.balanceOf(address(this)))) {
      if (maxAmount == 0) {
        return 0;
      }
      amount = maxAmount;
    }
    transferCollateralFrom(from, recipient, amount);
  }
}
