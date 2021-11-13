// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedPoolBase.sol';
import './MockWeightedRounds.sol';

contract MockWeightedPool is WeightedPoolBase {
  constructor(
    address collateral_,
    uint256 unitSize,
    WeightedPoolExtension extension
  ) WeightedPoolBase(unitSize, extension) InsurerPoolBase(collateral_) {
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
}
