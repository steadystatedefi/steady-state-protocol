// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedPoolBase.sol';

contract MockWeightedPool is WeightedPoolBase {
  constructor(address collateral_, uint256 unitSize) WeightedRoundsBase(unitSize) InsurerPoolBase(collateral_) {}
}
