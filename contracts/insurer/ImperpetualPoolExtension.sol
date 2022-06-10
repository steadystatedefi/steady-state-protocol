// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IJoinHandler.sol';
import './WeightedPoolExtension.sol';
import './PerpetualPoolBase.sol';

contract ImperpetualPoolExtension is WeightedPoolExtension {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(uint256 unitSize) WeightedPoolExtension(unitSize) {}

  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 excessCoverage,
    uint256 providedCoverage,
    uint256 receivedCoverage,
    DemandedCoverage memory
  ) internal override returns (uint256) {
    /* payout, excess, providedCoverage, receivedCoverage

    PERP: transferCollateralFrom(insured, address(this), receivedCoverage - payout);

    IMPERP: transferCollateralFrom(insured, address(this), givenCoverage - payout); or
    IMPERP: transferCollateralTo(insured, min(payout, providedCoverage*(1-CCD)) - givenCoverage); or

    */

    if (receivedCoverage > payoutValue) {
      // take back the unused provided coverage
      transferCollateralFrom(insured, address(this), receivedCoverage - payoutValue);
    }

    // this call is to consider / reinvest the released funds
    PerpetualPoolBase(address(this)).updateCoverageOnCancel(payoutValue, excessCoverage + (providedCoverage - payoutValue));
    // ^^ avoids code to be duplicated within WeightedPoolExtension to reduce contract size

    return payoutValue;
  }

  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory coverage
  ) internal override returns (uint256) {
    coverage;
    if (receivedCoverage > 0) {
      /* TODO apply MCD
          keep track of MCD-deducted amount 
          compare with maxDrawdown
          withheld or give out more
      */
      transferCollateral(insured, receivedCoverage);
    }
    return receivedCoverage;
  }
}
