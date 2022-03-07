// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/SafeERC20.sol';
import '../interfaces/ITreasury.sol';

///@dev The Treasury specifies the strategies approved to invest funds.
///  currently does not track the debt of each strategy
abstract contract Treasury {
  using SafeERC20 for IERC20;

  event StrategyBorrow(address startegy, address token, uint128 amount);
  event StrategyDeposit(address strategy, address token, uint128 amount);

  ///@dev This struct allows a strategy to keep their allowance when requestReturn() occurs
  struct Allowance {
    uint128 allowance; //The allowance is MAX borrowable
    uint128 borrowed; //Current amount borrowed
  }

  //TODO: If dToken (ERC1155) will track the amount of underlying (this is different than totalSupply)
  //  then only the invested amount should be stored to avoid extra store?
  struct Balance {
    //Calculating price per share use (balance + straegies.totalValue)
    uint128 deposited; //Amount deposited into the collateral fund by users
    uint128 balance; //Current (known) balance held directly by the fund. Includes collected earnings
    uint128 borrowed; //Amount "lent" out to strategies
    mapping(address => Allowance) allowance; //Allowance of this token per strategy
  }

  mapping(address => Balance) public assetBalances;

  //TODO: mapping(address=>ITreasuryStrategy[]) Keep track of all strategies using a token
  ITreasuryStrategy[] public activeStrategies;

  ///@dev A strategy borrowing funds after it has been approved
  function borrowFunds(address token, uint128 amount) external {
    Balance storage b = assetBalances[token];
    //The below statement will overflow if there is no more left to borrow
    b.allowance[msg.sender].allowance - b.allowance[msg.sender].borrowed - amount;
    b.allowance[msg.sender].borrowed += amount;
    b.balance -= amount;
    b.borrowed += amount;
    IERC20(token).safeTransfer(msg.sender, amount);

    emit StrategyBorrow(msg.sender, token, amount);
  }

  //TODO: Pulling vs ERC1363
  ///@dev Deposit funds into the Treasury, reduces amount borrowed and reduces strategey's borrow
  function depositFunds(address token, uint128 amount) external {
    IERC20(token).transferFrom(msg.sender, address(this), amount);
    Balance storage b = assetBalances[token];
    if (b.borrowed >= amount) {
      b.borrowed -= amount;
    } else {
      b.borrowed = 0;
    }

    if (amount > b.allowance[msg.sender].borrowed) {
      b.allowance[msg.sender].borrowed = 0;
    } else {
      b.allowance[msg.sender].borrowed -= amount;
    }

    b.balance += amount;

    emit StrategyDeposit(msg.sender, token, amount);
  }

  ///@dev Set the amount of tokens a strategy is currently allowed to take out
  function treasuryStrategyAllowance(
    address strategy,
    address token,
    uint128 amount
  ) internal {
    assetBalances[token].allowance[strategy].allowance = amount;
  }

  function _prepareWithdraw(address token, uint256 amount) internal {
    uint128 balance = uint128(IERC20(token).balanceOf(address(this)));
    assetBalances[token].balance = balance;

    if (balance < amount) {
      for (uint256 i = 0; i < activeStrategies.length; i++) {
        if (activeStrategies[i].requestReturn(token, uint128(amount - balance))) {
          //balance = uint128(IERC20(token).balanceOf(address(this)));
          if ((balance = assetBalances[token].balance) >= amount) {
            break;
          }
        }
      }
    }
    require(balance >= amount);
  }

  function _onDeposit(address token, uint256 amount) internal {
    require(amount < uint256(type(uint128).max));
    assetBalances[token].deposited += uint128(amount);
    assetBalances[token].balance += uint128(amount);
  }

  function _onWithdraw(address token, uint256 amount) internal {
    require(amount < uint256(type(uint128).max));
    assetBalances[token].deposited -= uint128(amount);
    assetBalances[token].balance -= uint128(amount);
  }

  ///@dev The number of tokens held directly by the treasury and its strategies,
  /// and the amount currently earned in those strategies
  function numberOf(address token) public view returns (uint128 amount) {
    amount += assetBalances[token].balance;
    for (uint256 i = 0; i < activeStrategies.length; i++) {
      amount += activeStrategies[i].totalValue(token);
    }
  }

  ///@dev Returns the amount earned/lost
  ///@return delta The difference of invested and current holdings
  ///@return rate The current lifetime WAD earning %
  function performanceOf(address token) public view returns (int256 delta, int256 rate) {
    /*
    for (uint256 i = 0; i < activeStrategies.length; i++) {
      performance += activeStrategies[i].deltaOf(token);
    }
    */
    uint256 deposited = assetBalances[token].deposited;
    delta = int256(uint256(numberOf(token))) - int256(deposited);

    int256 deltaWad = delta * 1e18;
    int256 depositsWad = int256(deposited) * 1e18;
    rate = ((deltaWad * 1e18 + depositsWad / 2) / depositsWad);
  }

  function treasuryAllowanceOf(address strategy, address token) external view returns (uint128) {
    return assetBalances[token].allowance[strategy].allowance;
  }

  function treasuryBorrowable(address strategy, address token) external view returns (uint128) {
    return assetBalances[token].allowance[strategy].allowance - assetBalances[token].allowance[strategy].borrowed;
  }
}
