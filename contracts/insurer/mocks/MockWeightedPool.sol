// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedPoolBase.sol';

contract MockWeightedPool is WeightedPoolBase {
  constructor(address collateral_, uint256 unitSize) WeightedRoundsBase(unitSize) InsurerPoolBase(collateral_) {}

  function internalBatchAppend(
    uint64 totalUnitsBeforeBatch,
    uint64 totalCoveredUnits,
    uint32 openRounds,
    uint64 unitCount
  ) internal pure override returns (uint24 rounds) {
    totalUnitsBeforeBatch;
    totalCoveredUnits;
    unitCount;
    return openRounds < 100 ? 100 : 0;
  }

  function internalPrepareJoin(address) internal override {}
}
