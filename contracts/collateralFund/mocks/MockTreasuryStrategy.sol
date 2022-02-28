// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//import '../../tools/tokens/IERC20.sol';
//import '../../tools/SafeERC20.sol';
import '../../interfaces/ITreasury.sol';
import './MockStablecoin.sol';

///@dev MockTreasuryStrategy implements a strategy on MockStablecoin. It simply
/// holds the tokens and can mint yield at will.
contract MockTreasuryStrategy is ITreasuryStrategy {
  ///@dev A normal strategy will probably have these variables as a struct in a mapping,
  /// as they may accept multiple underlyings
  uint128 public deposits;
  uint128 private earned;
  address private _underlying;
  ITreasury private treasury;

  constructor(address underlying_) {
    _underlying = underlying_;
  }

  function totalEarningsOf(address underlying) external view override returns (Earning[] memory) {
    Earning[] memory earnings = new Earning[](1);
    earnings[0] = (Earning(_underlying, earned));
    return earnings;
  }

  function totalEarned(address token) external view override returns (uint128) {
    return earned;
  }

  function totalValue(address token) external view override returns (uint128) {
    return deposits + earned;
  }

  ///@dev A normal strategy would have to take the tokens out of protocol they are earning yield in
  /// and then send them along.
  function requestReturn(address underlying, uint128 amount) external override returns (bool) {
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (balance >= amount) {
      IERC20(_underlying).transfer(address(treasury), amount);
    } else if (balance > 0) {
      IERC20(_underlying).transfer(address(treasury), balance);
    } else {
      return false;
    }

    return true;
  }

  ///@dev Mock how much has been earned
  function MockYield(uint128 amount) external {
    MockStable(_underlying).mint(address(this), amount);
    earned += amount;
  }
}
