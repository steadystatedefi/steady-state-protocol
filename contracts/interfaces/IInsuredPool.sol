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

  function rateBands() external view returns (InsuredRateBand[] memory bands, uint256 maxBands);

  function getInsurers() external view returns (address[] memory, address[] memory);
}

interface IReconcilableInsuredPool is IInsuredPool {
  function receivableByReconcileWithInsurer(address insurer) external view returns (ReceivableByReconcile memory);
}

struct ReceivableByReconcile {
  uint256 receivableCoverage;
  uint256 demandedCoverage;
  uint256 providedCoverage;
  uint256 rate;
  uint256 accumulated;
}

struct InsuredParams {
  uint128 minPerInsurer;
}

struct InsuredRateBand {
  uint64 premiumRate;
  uint96 coverageDemand;
}
