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
}

struct TotalCoverage {
  uint256 totalCoverable; // total demand that can be covered now (already balanced) - this value is not provided per-insured
  uint88 usableRounds;
  uint88 openRounds;
  uint64 batchCount;
}

interface IInsurerPoolCore is IInsurancePool {
  /// @dev indicates how the demand from insured pools is handled:
  /// * Chartered demand will be allocated without calling IInsuredPool, coverage units can be partially filled in.
  /// * Non-chartered (potential) demand can only be allocated after calling IInsuredPool.tryAddCoverage first, units can only be allocated in full.
  function charteredDemand() external view returns (bool);

  /// @dev amount of $IC tokens of a user. $IC * exchangeRate() = $CC
  function scaledBalanceOf(address account) external view returns (uint256);

  /// @dev returns reward / interest rate of the user
  function interestRate(address account) external view returns (uint256 rate, uint256 accumulatedRate);

  /// @dev returns ratio of $IC to $CC, this starts as 1 (RAY) and goes down with every insurance claim
  function exchangeRate() external view returns (uint256);
}

interface IInsurerPoolDemand is IInsurancePool, IJoinable {
  /// @dev size of collateral allocation chunk made by this pool
  function coverageUnitSize() external view returns (uint256);

  /// @dev can only be called by the collateral fund, when insured cancels coverage
  function onCoverageDeclined(address insured) external;

  /// @dev indicates how the demand from insured pools is handled:
  /// * Chartered demand will be allocated without calling IInsuredPool, coverage units can be partially filled in.
  /// * Non-chartered (potential) demand can only be allocated after calling IInsuredPool.tryAddCoverage first, units can only be allocated in full.
  function charteredDemand() external view override returns (bool);

  /// @dev can only be called by an accepted insured pool, adds demand for coverage
  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external returns (uint256 addedCount);

  /// @dev can only be called by an accepted insured pool, cancels only empty coverage units, returns number of cancelled units
  function cancelCoverageDemand(uint256 unitCount, bool hasMore) external returns (uint256 cancelledUnits);

  /// @dev returns coverage info for the insured
  function getCoverageDemand(address insured)
    external
    view
    returns (uint256 availableExtraCoverage, DemandedCoverage memory);

  /// @dev when charteredDemand is true and insured has incomplete demand, then this function will transfer $CC collected for the insured
  /// when charteredDemand is false or demand was fulfilled, then there is no need to call this function.
  function receiveDemandedCoverage(address insured)
    external
    returns (uint256 receivedExtraCoverage, DemandedCoverage memory);

  /// @dev amount of $IC tokens of a user. Weighted number of $IC tokens defines interest rate to be paid to the user
  function balanceOf(address account) external view returns (uint256);

  /// @dev total amount of $IC tokens
  function totalSupply() external view returns (uint256);

  /// @dev returns reward / interest rate of the user
  function interestRate(address account) external view returns (uint256 rate, uint256 accumulatedRate);

  /// @dev returns ratio of $IC to $CC, this starts as 1 (RAY) and goes down with every insurance claim
  function exchangeRate() external view returns (uint256 rate, uint256 accumulatedRate);
}

struct DemandedCoverage {
  uint256 totalDemand; // total demand added by insured to insurer
  uint256 totalCovered; // total coverage allocated by insured to insurer (can not exceed total demand)
  uint256 premiumRate; // total premium rate accumulated accross all units filled-in with coverage
  uint256 premiumAccumulatedRate; // time-cumulated of premiumRate
}

interface IInsuredPool {
  /// @dev address of the collateral fund and coverage token ($CC)
  function collateral() external view returns (address);

  /// @dev is called by insurer from or after requestJoin() to inform this insured pool if it was accepted or not
  function joinProcessed(bool accepted) external;

  /// @dev WIP called by insurer pool to cover full units ad-hoc, is used by direct insurer pools to facilitate user's choice
  function tryAddCoverage(uint256 unitCount, DemandedCoverage calldata current) external returns (uint256 addedCount);
}
