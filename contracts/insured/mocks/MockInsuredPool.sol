// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../InsuredPoolBase.sol';

contract MockInsuredPool is InsuredPoolBase {
  constructor(
    address collateral_,
    uint256 totalDemand,
    uint64 premiumRate,
    uint24 minUnitsPerInsurer,
    uint16 riskWeightPct,
    uint8 decimals
  )
    ERC20DetailsBase('InsuredPoolToken', '$DC', decimals)
    InsurancePoolBase(collateral_)
    InsuredPoolBase(totalDemand, premiumRate)
  {
    internalSetInsuredParams(InsuredParams({minUnitsPerInsurer: minUnitsPerInsurer, riskWeightPct: riskWeightPct}));
  }
}
