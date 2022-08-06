// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface IManagedYieldDistributor is ICollateralized {
  function registerStakeAsset(address asset, bool register) external;
}
