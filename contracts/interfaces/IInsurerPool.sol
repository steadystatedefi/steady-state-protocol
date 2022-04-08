// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import './IInsurancePool.sol';
import './IJoinable.sol';

struct DemandedCoverage {
  uint256 totalDemand; // total demand added to insurer
  uint256 totalCovered; // total coverage allocated by insurer (can not exceed total demand)
  uint256 pendingCovered; // coverage that is allocated, but can not be given yet (should reach unit size)
  uint256 premiumRate; // total premium rate accumulated accross all units filled-in with coverage
  uint256 totalPremium; // time-cumulated of premiumRate
  uint32 premiumUpdatedAt;
  uint32 premiumRateUpdatedAt;
}

struct TotalCoverage {
  uint256 totalCoverable; // total demand that can be covered now (already balanced) - this value is not provided per-insured
  uint88 usableRounds;
  uint88 openRounds;
  uint64 batchCount;
}

interface IInsurerPoolBase {
  /// @dev indicates how the demand from insured pools is handled:
  /// * Chartered demand will be allocated without calling IInsuredPool, coverage units can be partially filled in.
  /// * Non-chartered (potential) demand can only be allocated after calling IInsuredPool.tryAddCoverage first, units can only be allocated in full.
  function charteredDemand() external view returns (bool);

  function cancelCoverage(uint256 payoutRatio) external returns (uint256 payoutValue);
}

interface IInsurerPoolCore is IInsurancePool, IInsurerPoolBase {
  /// @dev amount of $IC tokens of a user. $IC * exchangeRate() = $CC
  function scaledBalanceOf(address account) external view returns (uint256);

  /// @dev returns reward / interest rate of the user
  function interestRate(address account) external view returns (uint256 rate, uint256 accumulatedRate);

  /// @dev returns ratio of $IC to $CC, this starts as 1 (RAY) and goes down with every insurance claim
  function exchangeRate() external view returns (uint256);

  function withdrawable(address account) external view returns (uint256 amount);

  function withdrawAll() external returns (uint256);
}

interface IInsurerPoolDemand is IInsurancePool, IInsurerPoolBase, IJoinable {
  function charteredDemand() external view override(IInsurerPoolBase, IJoinable) returns (bool);

  /// @dev size of collateral allocation chunk made by this pool
  function coverageUnitSize() external view returns (uint256);

  /// @dev can only be called by an accepted insured pool, adds demand for coverage
  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external returns (uint256 addedCount);

  /// @dev can only be called by an accepted insured pool, cancels only demanded, but not covered units
  /// @dev returns number of cancelled units, the pool will attempt to cancel _at least_ the given amount if possible
  function cancelCoverageDemand(uint256 unitCount) external returns (uint256 cancelledUnits);

  /// @dev returns coverage info for the insured
  function receivableDemandedCoverage(address insured)
    external
    view
    returns (uint256 receivedCoverage, DemandedCoverage memory);

  /// @dev when charteredDemand is true and insured has incomplete demand, then this function will transfer $CC collected for the insured
  /// when charteredDemand is false or demand was fulfilled, then there is no need to call this function.
  function receiveDemandedCoverage(address insured)
    external
    returns (uint256 receivedCoverage, DemandedCoverage memory);
}

interface IInsurerPool is IERC20, IInsurerPoolCore, IInsurerPoolDemand {
  function charteredDemand() external view override(IInsurerPoolBase, IInsurerPoolDemand) returns (bool);
}
