// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IInsuredPool is ICollateralized {
  /// @notice Called by insurer during or after requestJoin() to inform this insured if it was accepted or not
  /// @param accepted true if accepted by the insurer
  function joinProcessed(bool accepted) external;

  /// @notice Invoked by chartered pools to request more coverage demand
  /// @param amount a hint on demand amount, 0 means default
  /// @param maxAmount max demand amount
  /// @param loopLimit a max number of iterations
  function pullCoverageDemand(
    uint256 amount,
    uint256 maxAmount,
    uint256 loopLimit
  ) external returns (bool);

  /// @notice Get this insured params
  /// @return The insured params
  function insuredParams() external view returns (InsuredParams memory);

  /// @notice Directly offer coverage to the insured
  /// @param offeredAmount The amount of coverage being offered
  /// @return acceptedAmount The amount of coverage accepted by the insured
  /// @return rate The rate that the insured is paying for the coverage
  function offerCoverage(uint256 offeredAmount) external returns (uint256 acceptedAmount, uint256 rate);

  /// @dev Information about configured rate bands.
  /// @return bands with information of rate bands. Length is <= maxBands.
  /// @return maxBands with a maximum number of rate bands supported by this implementation of insured.
  function rateBands() external view returns (InsuredRateBand[] memory bands, uint256 maxBands);

  /// @dev Returns insurers joined by this insured
  /// @return nonChartered list with insurers without demand chartering. See ICharterable.
  /// @return chartered list with insurers with demand chartering. See ICharterable.
  function getInsurers() external view returns (address[] memory nonChartered, address[] memory chartered);
}

struct InsuredParams {
  /// @dev A minimum amount of coverage demand to be accepted by an insurer
  uint128 minPerInsurer;
}

/// @dev Information about the rate band
struct InsuredRateBand {
  /// @dev Premium rate for this band
  uint256 premiumRate;
  /// @dev Amount of coverage demand that can be given to insurer(s) under this premiumRate
  uint256 coverageDemand;
  /// @dev Amount of coverage demand already given to insurer(s) under this premiumRate
  uint256 assignedDemand;
}

interface IReconcilableInsuredPool is IInsuredPool {
  /// @return information about coverage that can be given to this insured after reconciliation with the `insurer`
  function receivableByReconcileWithInsurer(address insurer) external view returns (ReceivableByReconcile memory);
}

struct ReceivableByReconcile {
  /// @dev amount of coverage to be added to escrow (<= providedCoverage)
  uint256 receivableCoverage;
  /// @dev amount of coverage demanded
  uint256 demandedCoverage;
  /// @dev amount of demanded covered (<= demandedCoverage)
  uint256 providedCoverage;
  /// @dev current premium rate (for providedCoverage, considering rate bands)
  uint256 rate;
  /// @dev time-cumulated premium rate
  uint256 accumulated;
}
