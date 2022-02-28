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

  //TODO: If dToken (ERC1155) will track the amount of underlying (this is different than totalSupply)
  //  then only the invested amount should be stored to avoid extra store?
  struct Balance {
    //Calculating price per share use (balance + straegies.totalValue)
    uint128 deposited; //Amount deposited into the collateral fund by users
    uint128 balance; //Current (known) balance held directly by the fund. Includes collected earnings
    uint128 borrowed; //Amount "lent" out to strategies
    mapping(address => uint128) allowance;
  }

  mapping(address => Balance) public assetBalances;
  //mapping(address => mapping(address => uint128)) private startegyAllocations;

  ITreasuryStrategy[] public activeStrategies;

  function borrowFunds(address token, uint128 amount) external {
    require(assetBalances[token].allowance[msg.sender] >= amount);
    assetBalances[token].allowance[msg.sender] -= amount;
    assetBalances[token].balance -= amount;
    assetBalances[token].borrowed += amount;
    IERC20(token).safeTransfer(msg.sender, amount);

    emit StrategyBorrow(msg.sender, token, amount);
  }

  //TODO: Pulling vs ERC1363
  ///@dev Deposit funds into the Treasury and reduces amount borrowed. This DOES NOT
  /// check funds were originally borrowed by msg.sender
  function depositFunds(address token, uint128 amount) external {
    if (assetBalances[token].borrowed >= amount) {
      assetBalances[token].borrowed -= amount;
    } else {
      assetBalances[token].borrowed = 0;
    }

    assetBalances[token].balance += amount;

    emit StrategyDeposit(msg.sender, token, amount);
  }

  function setAllocation(
    address strategy,
    address token,
    uint128 amount
  ) internal {
    assetBalances[token].allowance[strategy] = amount;
  }

  function _prepareWithdraw(address token, uint256 amount) internal {
    uint128 balance = uint128(IERC20(token).balanceOf(address(this)));
    assetBalances[token].balance = balance;

    if (balance < amount) {
      for (uint256 i = 0; i < activeStrategies.length; i++) {
        if (activeStrategies[i].requestReturn(token, uint128(amount - balance))) {
          balance = uint128(IERC20(token).balanceOf(address(this)));
          if (balance >= amount) {
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
  function numberOf(address token) external view returns (uint128 amount) {
    amount += assetBalances[token].balance;
    for (uint256 i = 0; i < activeStrategies.length; i++) {
      amount += activeStrategies[i].totalValue(token);
    }
  }
}
