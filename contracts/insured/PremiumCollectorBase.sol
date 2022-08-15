// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumCollector.sol';
import '../interfaces/IPremiumSource.sol';
import '../tools/math/WadRayMath.sol';

import 'hardhat/console.sol';

abstract contract PremiumCollectorBase is IPremiumCollector, IPremiumSource {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  IERC20 private _premiumToken;
  uint256 private _collectedValue;

  uint32 private _rollingAdvanceWindow;
  uint160 private _minPrepayValue;

  function premiumToken() public view override(IPremiumCollector, IPremiumSource) returns (address) {
    return address(_premiumToken);
  }

  function _initializePremiumCollector(
    address token,
    uint160 minPrepayValue,
    uint32 rollingAdvanceWindow
  ) internal {
    Value.require(token != address(0));
    State.require(address(_premiumToken) == address(0));
    _premiumToken = IERC20(token);
    internalSetPrepay(minPrepayValue, rollingAdvanceWindow);
  }

  function internalSetPrepay(uint160 minPrepayValue, uint32 rollingAdvanceWindow) internal {
    _minPrepayValue = minPrepayValue;
    _rollingAdvanceWindow = rollingAdvanceWindow;
  }

  function internalExpectedPrepay(uint256 atTimestamp) internal view virtual returns (uint256);

  function internalPriceOf(address) internal view virtual returns (uint256);

  function internalPullPriceOf(address) internal virtual returns (uint256);

  function _expectedPrepay(uint256 atTimestamp) internal view returns (uint256) {
    uint256 required = internalExpectedPrepay(atTimestamp + _rollingAdvanceWindow);
    uint256 minPrepayValue = _minPrepayValue;
    if (minPrepayValue > required) {
      required = minPrepayValue;
    }

    uint256 collected = _collectedValue;
    return collected >= required ? 0 : required - collected;
  }

  function expectedPrepay(uint256 atTimestamp) public view override returns (uint256) {
    uint256 value = _expectedPrepay(atTimestamp);
    return value == 0 ? 0 : value.wadDiv(internalPriceOf(address(_premiumToken)));
  }

  function expectedPrepayAfter(uint32 timeDelta) external view override returns (uint256 amount) {
    return expectedPrepay(uint32(block.timestamp) + timeDelta);
  }

  function internalWithdrawPrepay(address recipient, uint256 amount) internal returns (uint256) {
    IERC20 token = _premiumToken;

    uint256 balance = token.balanceOf(address(this));
    if (balance > 0) {
      uint256 expected = _expectedPrepay(uint32(block.timestamp));
      if (expected > 0) {
        uint256 price = internalPullPriceOf(address(_premiumToken));
        if (price != 0) {
          expected = expected.wadDiv(price);
          balance = expected >= balance ? 0 : balance - expected;
        } else {
          balance = 0;
        }
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

    return amount;
  }

  function collateral() public view virtual returns (address);

  function internalReservedCollateral() internal view virtual returns (uint256);

  function internalCollectPremium(
    address token,
    uint256 amount,
    uint256 value
  ) internal {
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
