// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../ImperpetualPoolBase.sol';
import './MockWeightedRounds.sol';

contract MockImperpetualPool is ImperpetualPoolBase {
  constructor(
    address collateral_,
    uint256 unitSize,
    uint8 decimals,
    ImperpetualPoolExtension extension
  ) ERC20DetailsBase('ImperpetualPoolToken', '$IC', decimals) ImperpetualPoolBase(unitSize, extension) Collateralized(collateral_) {
    _joinHandler = address(this);
    internalSetPoolParams(
      WeightedPoolParams({
        maxAdvanceUnits: 10000,
        minAdvanceUnits: 1000,
        riskWeightTarget: 1000, // 10%
        minInsuredShare: 100, // 1%
        maxInsuredShare: 4000, // 25%
        minUnitsPerRound: 20,
        maxUnitsPerRound: 20,
        overUnitsPerRound: 30,
        maxDrawdownInverse: 9000 // 90%
      })
    );
  }

  function setPoolParams(WeightedPoolParams calldata params) external {
    internalSetPoolParams(params);
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals(type(uint256).max);
  }

  function getExcessCoverage() external view returns (uint256) {
    return _excessCoverage;
  }

  function setExcessCoverage(uint256 v) external {
    _excessCoverage = v;
  }

  function internalOnCoverageRecovered() internal override {}

  function receivableDemandedCoverage(address insured) external view returns (uint256 availableCoverage, DemandedCoverage memory coverage) {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  uint256 public receivedCoverage;

  function receiveDemandedCoverage(address insured, uint16 loopLimit) external returns (DemandedCoverage memory coverage) {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = loopLimit == 0 ? ~params.loopLimit : loopLimit;

    coverage = internalUpdateCoveredDemand(params);
    receivedCoverage += params.receivedCoverage;
  }

  function dump() external view returns (Dump memory) {
    return _dump();
  }

  function dumpInsured(address insured)
    external
    view
    returns (
      Rounds.InsuredEntry memory,
      Rounds.Demand[] memory,
      Rounds.Coverage memory,
      Rounds.CoveragePremium memory
    )
  {
    return _dumpInsured(insured);
  }

  function getUnadjusted()
    external
    view
    returns (
      uint256 total,
      uint256 pendingCovered,
      uint256 pendingDemand
    )
  {
    return internalGetUnadjustedUnits();
  }

  function applyAdjustments() external {
    internalApplyAdjustmentsToTotals();
  }
}
