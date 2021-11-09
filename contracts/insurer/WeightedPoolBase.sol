// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IInsurerPool.sol';
import './InsurerPoolBase.sol';
import './WeightedRoundsBase.sol';

abstract contract WeightedPoolBase is WeightedRoundsBase, InsurerPoolBase {
  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  function charteredDemand() public pure override returns (bool) {
    return true;
  }

  function onCoverageDeclined(address insured) external override {}

  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external override returns (uint256 addedCount) {}

  function cancelCoverageDemand(uint256 unitCount, bool hasMore) external override returns (uint256 cancelledUnits) {}

  function getCoverageDemand(address insured)
    external
    view
    override
    returns (uint256 availableExtraCoverage, DemandedCoverage memory)
  {}

  function receiveDemandedCoverage(address insured)
    external
    override
    returns (uint256 receivedExtraCoverage, DemandedCoverage memory)
  {}

  function internalRoundLimits(
    uint64 totalUnitsBeforeBatch,
    uint64 demandedUnits,
    uint256 maxShare
  )
    internal
    override
    returns (
      uint16 maxAddUnitsPerRound,
      uint16 minUnitsPerRound,
      uint16 maxUnitsPerRound
    )
  {}

  function internalBatchSplit(
    uint24 batchRounds,
    uint64 demandedUnits,
    uint24 remainingUnits,
    uint64 minUnits
  ) internal override returns (uint24 splitRounds) {}

  function internalHandleInvestment(
    address investor,
    uint256 amount,
    bytes memory data
  ) internal override {
    if (data.length > 0) {
      abi.decode(data, ());
    }
    investor;
    (amount, ) = super.internalAddCoverage(amount, type(uint256).max);
    // excessCoverage += amount;
  }
}
