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

  constructor(address _treasury, address underlying_) {
    treasury = ITreasury(_treasury);
    _underlying = underlying_;
    IERC20(_underlying).approve(_treasury, type(uint256).max);
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
    if (balance < amount) {
      if (balance == 0) {
        return false;
      }
      amount = uint128(balance);
    }
    treasury.depositFunds(_underlying, amount);
    onWithdraw(amount);
    /*
    if (balance >= amount) {
      //IERC20(_underlying).transfer(address(treasury), amount);
      //treasury.depositFunds(_underlying, amount);
    } else if (balance > 0) {
      //IERC20(_underlying).transfer(address(treasury), balance);
      treasury.depositFunds(_underlying, uint128(balance));
    } else {
      return false;
    }
    */

    return true;
  }

  function onWithdraw(uint128 amount) internal {
    if (earned >= amount) {
      earned -= amount;
      return;
    } else {
      amount -= earned;
      earned = 0;
    }
    deposits -= amount;
  }

  ///@dev Mock how much has been earned
  function MockYield(uint128 amount) external {
    MockStable(_underlying).mint(address(this), amount);
    earned += amount;
  }

  function Borrow(uint128 amount) external {
    treasury.borrowFunds(_underlying, amount);
    deposits += amount;
  }

  function Repay(uint128 amount) external {
    treasury.depositFunds(_underlying, amount);
    onWithdraw(amount);
  }
}
