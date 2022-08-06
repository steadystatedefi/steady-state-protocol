// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';
import '../tools/tokens/IERC20.sol';

interface IYieldStakeAsset is ICollateralized {
  function collateralSupply() external view returns (uint256);

  function totalSupply() external view returns (uint256);
}
