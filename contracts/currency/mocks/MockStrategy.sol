// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IReinvestStrategy.sol';
import '../../tools/tokens/IERC20.sol';

contract MockStrategy is IReinvestStrategy {
  mapping(address => uint256) public investedValueOf;

  function connectAssetBefore(address) external returns (bool) {
    return true;
  }

  function connectAssetAfter(address token) external {}

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
    uint256 minLimit
  ) external returns (uint256 amountBefore) {
    amountBefore = investedValueOf[token];
    if (minLimit > amountBefore) {
      return 0;
    }
    if (amount > (amountBefore - minLimit)) {
      amount = amountBefore - minLimit;
    }

    IERC20(token).approve(to, amount);
    investedValueOf[token] -= amount;
  }

  function deltaYield(address token, int256 amount) external {
    if (amount >= 0) {
      investedValueOf[token] += uint256(amount);
      IERC20(token).transferFrom(msg.sender, address(this), uint256(amount));
    } else {
      investedValueOf[token] -= uint256(amount * -1);
    }
  }

  function approve(
    address token,
    address to,
    uint256 amount
  ) external {
    IERC20(token).approve(to, amount);
  }

  function attachManager(address manager, bool attach) external returns (bool) {
    return true;
  }

  function name() external view returns (string memory) {
    return 'MockStrat';
  }
}
