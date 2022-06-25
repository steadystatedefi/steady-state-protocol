// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeOwnable.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import './CollateralFundBase.sol';

contract CollateralFundZLBase is CollateralFundBase {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  struct UserBalance {
    uint112 asset;
    uint112 coverage;
    uint32 at;
  }

  mapping(address => mapping(address => UserBalance)) private _balances; // [token][account]

  function _zeroLossDuration() private view returns (uint256) {}

  function internalDeposit(
    address to,
    address token,
    uint256 amount,
    uint256 value
  ) internal override {
    UserBalance storage balance = _balances[token][to];
    uint32 at = balance.at;

    if (at != 1) {
      if (at == 0) {
        balance.at = uint32(block.timestamp);
      } else if (_zeroLossDuration() + at <= block.timestamp) {
        balance.at = 1;
        return;
      }
      balance.asset += uint112(amount); // TODO
      balance.coverage += uint112(value); // TODO
    }
  }

  function _withdrawCalc(
    uint112 x0,
    uint112 y0,
    uint256 x
  )
    private
    pure
    returns (
      uint112,
      uint112,
      uint256,
      uint256 y
    )
  {
    if (x0 > x) {
      y = (uint256(y0) * x).divUp(x0);
      unchecked {
        x0 -= uint112(x);
        y0 -= uint112(y);
      }
    } else {
      unchecked {
        x -= x0;
      }
      y = y0;
      (x0, y0) = (0, 0);
    }
    return (x0, y0, x, y);
  }

  function internalWithdrawAmount(
    address token,
    address from,
    uint256 amount
  ) internal override returns (uint256, uint256 value) {
    UserBalance storage balance = _balances[token][from];
    uint32 at = balance.at;
    if (at > 1) {
      if (_zeroLossDuration() + at <= block.timestamp) {
        balance.at = 1;
      } else {
        uint112 x = balance.asset;
        if (x > 0) {
          (balance.asset, balance.coverage, amount, value) = _withdrawCalc(x, balance.coverage, amount);
        }
      }
    }
    return (amount, value);
  }

  function internalWithdrawValue(
    address token,
    address from,
    uint256 value
  ) internal override returns (uint256 amount, uint256) {
    UserBalance storage balance = _balances[token][from];
    uint32 at = balance.at;
    if (at > 1) {
      if (_zeroLossDuration() + at <= block.timestamp) {
        balance.at = 1;
      } else {
        uint112 x = balance.coverage;
        if (x > 0) {
          (balance.coverage, balance.asset, value, amount) = _withdrawCalc(x, balance.asset, value);
        }
      }
    }
    return (amount, value);
  }
}
