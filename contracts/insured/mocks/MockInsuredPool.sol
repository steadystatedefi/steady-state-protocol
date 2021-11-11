// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../InsuredPoolBase.sol';

contract MockInsuredPool is InsuredPoolBase {
  constructor(
    address collateral_,
    uint256 totalDemand,
    uint64 premiumRate
  ) InsuredBalancesBase(collateral_) InsuredPoolBase(totalDemand, premiumRate) {
    internalSetInsuredParams(
      InsuredParams({
        minUnitsPerInsurer: 10,
        riskWeightPct: 1000 // 10%
      })
    );
  }
}
