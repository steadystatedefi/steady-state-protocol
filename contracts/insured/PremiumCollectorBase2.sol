// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IPremiumCollector.sol';
import '../interfaces/IPremiumSource.sol';

import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IProtocol.sol';
import '../tools/math/WadRayMath.sol';

import 'hardhat/console.sol';

abstract contract PremiumCollectorBase2 is IPremiumCollector, IPremiumSource {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  IERC20 private _premiumToken;
  uint256 private _collectedValue;

  modifier onlyWithdrawRole() virtual {
    _;
  }

  modifier onlyPremiumDispenser() virtual {
    _;
  }

  function premiumToken() external view override(IPremiumCollector, IPremiumSource) returns (address) {
    return address(_premiumToken);
  }

  function internalExpectedPrepay(uint256 atTimestamp) internal view virtual returns (uint256);

  function expectedPrepay(uint256 atTimestamp) external view override returns (uint256) {
    return internalExpectedPrepay(atTimestamp);
  }

  function expectedPrepayAfter(uint32 timeDelta) external view override returns (uint256) {
    return internalExpectedPrepay(uint32(block.timestamp) + timeDelta);
  }

  function priceOf(address) internal virtual returns (uint256);

  function withdrawPrepay(address recipient, uint256 amount) external override onlyWithdrawRole {
    IERC20 token = _premiumToken;

    uint256 balance = token.balanceOf(address(this));
    if (balance > 0) {
      uint256 expected = internalExpectedPrepay(uint32(block.timestamp));
      uint256 collected = _collectedValue;
      if (expected > collected) {
        expected = (expected - collected).wadDiv(priceOf(address(token)));
        balance = expected >= balance ? 0 : balance - expected;
      }
    }
    if (amount == type(uint256).max) {
      amount = balance;
    } else {
      Value.require(amount <= balance);
    }

    if (amount > 0) {
      token.safeTransfer(recipient, amount);
    }
  }

  function collectPremium(
    address token,
    uint256 amount,
    uint256 value
  ) external override onlyPremiumDispenser {
    Value.require(token == address(_premiumToken));

    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
      if (amount > balance) {
        value = (value * balance) / amount;
        if (value == 0) {
          return;
        }
        amount = balance;
      }
      IERC20(token).safeTransfer(msg.sender, amount);
      _collectedValue += value;
    }
  }
}
