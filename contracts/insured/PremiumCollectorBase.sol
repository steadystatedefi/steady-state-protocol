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
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumSource.sol';

import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IProtocol.sol';
import '../tools/math/WadRayMath.sol';

import 'hardhat/console.sol';

abstract contract PremiumCollectorBase is IPremiumCollector, IPremiumSource {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  IERC20 private _premiumToken;
  uint256 private _collectedValue;

  uint32 private _rollingAdvanceWindow;
  uint160 private _minPrepayValue;

  modifier onlyWithdrawalRole() virtual {
    _; // TODO
  }

  modifier onlyPremiumDistributorOf(address actuary) virtual {
    _;
  }

  function premiumToken() external view override(IPremiumCollector, IPremiumSource) returns (address) {
    return address(_premiumToken);
  }

  function internalExpectedPrepay(uint256 atTimestamp) internal view virtual returns (uint256);

  function priceOf(address) internal view virtual returns (uint256);

  function expectedPrepay(uint256 atTimestamp) public view override returns (uint256) {
    uint256 required = internalExpectedPrepay(atTimestamp + _rollingAdvanceWindow);
    uint256 minPrepayValue = _minPrepayValue;
    if (minPrepayValue > required) {
      required = minPrepayValue;
    }

    uint256 collected = _collectedValue;
    return collected >= required ? 0 : (required - collected).wadDiv(priceOf(address(_premiumToken)));
  }

  function expectedPrepayAfter(uint32 timeDelta) external view override returns (uint256 amount) {
    return expectedPrepay(uint32(block.timestamp) + timeDelta);
  }

  function withdrawPrepay(address recipient, uint256 amount) external override onlyWithdrawalRole {
    IERC20 token = _premiumToken;

    uint256 balance = token.balanceOf(address(this));
    if (balance > 0) {
      uint256 expected = expectedPrepay(uint32(block.timestamp));
      balance = expected >= balance ? 0 : balance - expected;
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

  function collateral() public view virtual returns (address);

  function internalReservedCollateral() internal view virtual returns (uint256);

  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external override onlyPremiumDistributorOf(actuary) {
    uint256 balance = IERC20(token).balanceOf(address(this));

    if (balance > 0) {
      if (token == collateral()) {
        balance -= internalReservedCollateral();
        if (amount > balance) {
          amount = balance;
        }
        value = amount;
      } else {
        Value.require(token == address(_premiumToken));
        if (amount > balance) {
          value = (value * balance) / amount;
          amount = balance;
        }
      }

      if (value > 0) {
        IERC20(token).safeTransfer(msg.sender, amount);
        _collectedValue += value;
      }
    }
  }
}
