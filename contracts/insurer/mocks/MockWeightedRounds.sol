// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedRoundsBase.sol';

contract MockWeightedRounds is WeightedRoundsBase {
  uint256 public excessCoverage;

  constructor(uint256 unitSize) WeightedRoundsBase(unitSize) {}

  function addCoverageDemand(
    address insured,
    uint64 unitCount,
    uint40 premiumRate,
    bool hasMore
  ) external returns (uint64) {
    AddCoverageDemandParams memory params;
    params.insured = insured;
    params.premiumRate = premiumRate;
    params.loopLimit = ~params.loopLimit;
    hasMore;

    return super.internalAddCoverageDemand(unitCount, params);
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
    uint24 batchRounds,
    uint64 demandedUnits,
    uint16 maxShare
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
    batchRounds;
    return (_maxAddUnitsPerRound, _minUnitsPerRound, _maxUnitsPerRound);
  }

  uint32 private _splitRounds = type(uint32).max;

  function setBatchSplit(uint32 splitRounds) external {
    _splitRounds = splitRounds;
  }

  function internalBatchSplit(
    uint64 demandedUnits,
    uint64 minUnits,
    uint24 batchRounds,
    uint24 remainingUnits
  ) internal view override returns (uint24 splitRounds) {
    minUnits;
    batchRounds;
    demandedUnits;
    remainingUnits;
    return _splitRounds <= type(uint24).max ? uint24(_splitRounds) : remainingUnits;
  }

  function internalBatchAppend(
    uint64 totalUnitsBeforeBatch,
    uint64 totalCoveredUnits,
    uint32 openRounds,
    uint64 unitCount
  ) internal pure override returns (uint24 rounds) {
    totalUnitsBeforeBatch;
    totalCoveredUnits;
    openRounds;
    return unitCount > type(uint24).max ? type(uint24).max : uint24(unitCount);
  }

  function addCoverage(uint256 amount) external {
    (amount, , ) = super.internalAddCoverage(amount, type(uint256).max);
    excessCoverage += amount;
  }

  function dump() external view returns (Dump memory) {
    return _dump();
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals(type(uint256).max);
  }

  function getCoverageDemand(address insured)
    external
    view
    returns (uint256 availableCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  uint256 public receivedCoverage;

  function receiveDemandedCoverage(address insured, uint16 loopLimit)
    external
    returns (DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = loopLimit;

    coverage = internalUpdateCoveredDemand(params);
    receivedCoverage += params.receivedCoverage;
  }
}
