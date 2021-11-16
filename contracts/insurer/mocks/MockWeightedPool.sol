// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedPoolBase.sol';
import './MockWeightedRounds.sol';

contract MockWeightedPool is WeightedPoolBase {
  constructor(
    address collateral_,
    uint256 unitSize,
    uint8 decimals,
    WeightedPoolExtension extension
  )
    ERC20DetailsBase('WeightedPoolToken', '$IC', decimals)
    WeightedPoolBase(unitSize, extension)
    InsurancePoolBase(collateral_)
  {
    _joinHandler = address(this);
    internalSetPoolParams(
      WeightedPoolParams({
        maxAdvanceUnits: 10000,
        minAdvanceUnits: 1000,
        riskWeightTarget: 1000, // 10%
        minInsuredShare: 100, // 1%
        maxInsuredShare: 4000, // 25%
        maxUnitsPerRound: 20,
        minUnitsPerRound: 20
      })
    );
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals(type(uint256).max);
  }

  function receivableDemandedCoverage(address insured)
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
    params.loopLimit = loopLimit == 0 ? ~params.loopLimit : loopLimit;

    coverage = internalUpdateCoveredDemand(params);
    receivedCoverage += params.receivedCoverage;
  }
}
