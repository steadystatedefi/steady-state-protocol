// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IPremiumSource.sol';
import '../../tools/tokens/IERC20.sol';
import '../../tools/Errors.sol';

//import '../../interfaces/IPremiumDistributor.sol';
//import '../../insured/PremiumCollectorBase.sol';

contract MockPremiumSource is IPremiumSource {
  address public premiumToken;
  address public collateral;

  constructor(address _premiumToken, address _collateral) {
    premiumToken = _premiumToken;
    collateral = _collateral;
  }

  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external {
    uint256 balance = IERC20(token).balanceOf(address(this));

    if (balance > 0) {
      if (token == collateral) {
        if (amount > balance) {
          amount = balance;
        }
        value = amount;
      } else {
        Value.require(token == address(premiumToken));
        if (amount > balance) {
          value = (value * balance) / amount;
          amount = balance;
        }
      }

      if (value > 0) {
        IERC20(token).transfer(msg.sender, amount);
        //_collectedValue += value;
      }
    }
  }
}
