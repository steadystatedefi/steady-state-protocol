// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';
import './ICharterable.sol';

interface IDemandableCoverage {
  /// @dev size of collateral allocation chunk made by this pool
  function coverageUnitSize() external view returns (uint256);

  /// @notice Add demand for coverage
  /// @dev can only be called by an accepted insured pool
  /// @param unitCount Number of *units* of coverage demand to add
  /// @param premiumRate The rate paid on the coverage
  /// @param hasMore Whether the insured has more demand it would like to request after this
  /// @return addedCount Number of units of demand that were actually added
  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore,
    uint256 loopLimit
  ) external returns (uint256 addedCount);

  /// @notice Cancel coverage that has been demanded, but not filled yet
  /// @dev can only be called by an accepted insured pool
  /// @param unitCount The number of units that wishes to be cancelled
  /// @return cancelledUnits The amount of units that were cancelled
  /// @return rateBands Distribution of cancelled uints by rate-bands, each aeeay value has higher 40 bits as rate, and the rest as number of units
  function cancelCoverageDemand(
    address insured,
    uint256 unitCount,
    uint256 loopLimit
  ) external returns (uint256 cancelledUnits, uint256[] memory rateBands);
}

interface ICancellableCoverage {
  /// @dev size of collateral allocation chunk made by this pool
  function coverageUnitSize() external view returns (uint256);

  /// @notice Cancel coverage for the sender
  /// @dev Called by insureds
  /// @param payoutRatio The RAY ratio of how much of provided coverage should be paid out
  /// @dev e.g payoutRatio = 5e26 means 50% of coverage is paid
  /// @return payoutValue The amount of coverage paid out to the insured
  function cancelCoverage(address insured, uint256 payoutRatio) external returns (uint256 payoutValue);
}

interface IReceivableCoverage is ICancellableCoverage {
  ///@notice Get the amount of coverage demanded and filled, and the total premium rate and premium charged
  ///@param insured The insured pool
  ///@return availableCoverage The amount coverage in terms of $CC
  ///@return coverage All the details relating to the coverage, demand and premium
  function receivableDemandedCoverage(address insured, uint256 loopLimit)
    external
    view
    returns (uint256 availableCoverage, DemandedCoverage memory coverage);

  /// @notice Transfer the amount of coverage that been filled to the insured since last called
  /// @dev Only should be called when charteredDemand is true
  /// @dev No use in calling this after coverage demand is fully fulfilled
  /// @param insured The insured to be updated
  /// @return receivedCoverage amount of coverage the Insured received
  /// @return receivedCollateral amount of collateral sent to the Insured
  /// @return coverage Up to date information for this insured
  function receiveDemandedCoverage(address insured, uint256 loopLimit)
    external
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
      DemandedCoverage memory
    );
}

interface ICoverageDistributor is IDemandableCoverage, IReceivableCoverage {
  function coverageUnitSize() external view override(ICancellableCoverage, IDemandableCoverage) returns (uint256);
}

struct DemandedCoverage {
  /// @dev total demand added to the insurer
  uint256 totalDemand;
  /// @dev total coverage allocated by the insurer (can not exceed total demand)
  uint256 totalCovered;
  /// @dev coverage that is allocated, but can not be reconciled yet (should reach unit size)
  uint256 pendingCovered;
  /// @dev total premium rate accumulated accross all units filled-in with coverage
  uint256 premiumRate;
  /// @dev time-cumulated of premiumRate
  uint256 totalPremium;
  /// @dev timestamp of totalPremium value (at which time it was calculated)
  uint32 premiumUpdatedAt;
  /// @dev timestamp of premiumRate value (at which time it is known to be updated)
  uint32 premiumRateUpdatedAt;
}

struct TotalCoverage {
  /// @dev total demand that can be covered now (sufficiently balanced)
  uint256 totalCoverable;
  /// @dev total number of sufficiently balanced rounds (with demand that can be covered)
  uint88 usableRounds;
  /// @dev total number of rounds added, but with demand insufficiently balanced (can not be covered)
  uint88 openRounds;
  /// @dev total number batches not fully covered yet (including open ones).
  uint64 batchCount;
}
