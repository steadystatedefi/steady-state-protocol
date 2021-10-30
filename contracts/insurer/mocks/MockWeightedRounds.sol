// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedRoundsBase.sol';

contract MockWeightedRounds is WeightedRoundsBase {
  uint256 public excessCoverage;

  constructor(uint256 unitSize) WeightedRoundsBase(unitSize) {}

  function addCoverageDemand(
    address insured,
    uint64 unitCount,
    uint128 premiumRate,
    bool hasMore
  ) external returns (uint64) {
    AddCoverageDemandParams memory params;
    params.insured = insured;
    params.premiumRate = premiumRate;
    params.hasMore = hasMore;

    (unitCount, ) = super.internalAddCoverageDemand(unitCount, type(uint256).max, params);
    return unitCount;
  }

  uint16 private _maxAddUnitsPerRound = 1;
  uint16 private _minUnitsPerRound = 2;
  uint16 private _maxUnitsPerRound = 3;

  function setRoundLimits(
    uint16 maxAddUnitsPerRound,
    uint16 minUnitsPerRound,
    uint16 maxUnitsPerRound
  ) external {
    _maxAddUnitsPerRound = maxAddUnitsPerRound;
    _minUnitsPerRound = minUnitsPerRound;
    _maxUnitsPerRound = maxUnitsPerRound;
  }

  function internalRoundLimits(
    uint64 totalUnitsBeforeBatch,
    uint64 demandedUnits,
    uint256 maxShare
  )
    internal
    view
    override
    returns (
      uint16 maxAddUnitsPerRound,
      uint16 minUnitsPerRound,
      uint16 maxUnitsPerRound
    )
  {
    totalUnitsBeforeBatch;
    demandedUnits;
    maxShare;
    return (_maxAddUnitsPerRound, _minUnitsPerRound, _maxUnitsPerRound);
  }

  uint32 private _splitRounds = type(uint32).max;

  function setBatchSplit(uint32 splitRounds) external {
    _splitRounds = splitRounds;
  }

  function internalBatchSplit(
    uint24 batchRounds,
    uint64 demandedUnits,
    uint24 remainingUnits,
    uint64 minUnits
  ) internal view override returns (uint24 splitRounds) {
    minUnits;
    batchRounds;
    demandedUnits;
    remainingUnits;
    return _splitRounds <= type(uint24).max ? uint24(_splitRounds) : remainingUnits;
  }

  function addCoverage(uint256 amount) external {
    (amount, ) = super.internalAddCoverage(amount, type(uint256).max);
    excessCoverage += amount;
  }

  function dump() external view returns (Dump memory) {
    return _dump();
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals();
  }
}
