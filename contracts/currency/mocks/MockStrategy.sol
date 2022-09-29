// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IReinvestStrategy.sol';
import '../../tools/tokens/IERC20.sol';

contract MockStrategy is IReinvestStrategy {
  mapping(address => uint256) public investedValueOf;

  function investFrom(
    address token,
    address from,
    uint256 amount
  ) external {
    investedValueOf[token] += amount;
    IERC20(token).transferFrom(from, address(this), amount);
  }

  function approveDivest(
    address token,
    address to,
    uint256 amount,
    uint256
  ) external returns (uint256 amountBefore) {
    amountBefore = investedValueOf[token];
    IERC20(token).approve(to, amount);
    investedValueOf[token] -= amount;
  }

  function deltaYield(address token, int256 amount) external {
    if (amount >= 0) {
      investedValueOf[token] += uint256(amount);
      IERC20(token).transferFrom(msg.sender, address(this), uint256(amount));
    } else {
      investedValueOf[token] -= uint256(amount);
      IERC20(token).transfer(address(0), uint256(amount));
    }
  }
}
