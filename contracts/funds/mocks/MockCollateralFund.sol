// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/tokens/IERC1363.sol';
import '../../interfaces/ICollateralFund.sol';

contract MockCollateralFund is ICollateralFund {
  function deposit(
    address asset,
    uint256 amount,
    address to,
    uint256 referralCode
  ) external override {}

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external override {}

  function invest(address insurer, uint256 amount) external override {
    bytes memory params;
    _transferAndCall(insurer, amount, params);
  }

  function investWithParams(
    address insurer,
    uint256 amount,
    bytes calldata params
  ) external override {
    _transferAndCall(insurer, amount, params);
  }

  function balanceOf(address account) external view override returns (uint256) {}

  function totalSupply() external view override returns (uint256) {}

  function transfer(address, uint256) external pure override returns (bool) {
    return true;
  }

  function transferAndCall(address to, uint256 value) external returns (bool) {
    return _transferAndCall(to, value, '');
  }

  function transferAndCall(
    address to,
    uint256 value,
    bytes memory data
  ) external returns (bool) {
    return _transferAndCall(to, value, data);
  }

  function _transferAndCall(
    address to,
    uint256 value,
    bytes memory data
  ) private returns (bool) {
    ERC1363.callReceiver(to, msg.sender, msg.sender, value, data);
    return true;
  }

  function healthFactorOf(address account) external view override returns (uint256 hf, int256 balance) {}

  function investedCollateral() external view override returns (uint256) {}

  function collateralPerformance() external view override returns (uint256 rate, uint256 accumulated) {}

  function getReserveAssets()
    external
    view
    override
    returns (address[] memory assets, address[] memory depositTokens)
  {}
}
