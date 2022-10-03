// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/SafeERC20.sol';
import '../../tools/Errors.sol';
import './ReinvestStrategyBase.sol';
import './AaveTypes.sol';

contract AaveStrategy is ReinvestStrategyBase {
  IAaveLendingPool private immutable _pool;
  uint8 private immutable _version;

  mapping(address => address) private _reserveTokens;

  constructor(
    address manager,
    address pool,
    uint8 version
  ) ReinvestStrategyBase(manager) {
    Value.require(pool != address(0));
    Value.require(version >= 2 && version <= 3);
    _pool = IAaveLendingPool(pool);
    _version = version;
  }

  function connectAssetBefore(address token) external override onlyManager returns (bool) {
    address aToken;
    if (_version == 3) {
      aToken = IAaveLendingPoolV3(address(_pool)).getReserveData(token).aTokenAddress;
    } else if (_version == 2) {
      aToken = IAaveLendingPoolV2(address(_pool)).getReserveData(token).aTokenAddress;
    }
    _reserveTokens[token] = aToken;
    SafeERC20.safeApprove(IERC20(token), address(_pool), type(uint256).max);
    return aToken != address(0);
  }

  function connectAssetAfter(address token) external override onlyManager {
    State.require(_reserveTokens[token] != address(0));

    // this reduces gas costs on withdrawals
    _pool.setUserUseReserveAsCollateral(token, false);
  }

  function investFrom(
    address token,
    address from,
    uint256 amount
  ) external override onlyManager {
    SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
    _pool.deposit(token, amount, address(this), 0);
  }

  function approveDivest(
    address token,
    address to,
    uint256 amount,
    uint256 minLimit
  ) external override onlyManager returns (uint256 amountBefore) {
    address aToken = _reserveTokens[token];
    State.require(aToken != address(0));

    amountBefore = IERC20(aToken).balanceOf(address(this));
    if (amountBefore > minLimit) {
      minLimit = amountBefore - minLimit;
      if (amount > minLimit) {
        amount = minLimit;
      }

      _pool.withdraw(token, amount, address(this));
      SafeERC20.safeApprove(IERC20(token), to, amount);
    }
  }

  function investedValueOf(address token) external view override returns (uint256) {
    address aToken = _reserveTokens[token];
    return aToken == address(0) ? 0 : IERC20(aToken).balanceOf(address(this));
  }

  function setRewardClaimer(address incentivesController, address claimer) external onlyManager {
    IAaveIncentivesController(incentivesController).setClaimer(address(this), claimer);
  }
}
