// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './WeightedPoolExtension.sol';
import './PerpetualPoolBase.sol';

/// @dev NB! MUST HAVE NO STORAGE
contract PerpetualPoolExtension is WeightedPoolExtension {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedPoolConfig(acl, unitSize, collateral_) {}

  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 excessCoverage,
    uint256 providedCoverage,
    uint256 receivedCoverage
  ) internal override returns (uint256) {
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
    DemandedCoverage memory
  ) internal override returns (uint256) {
    if (receivedCoverage > 0) {
      transferCollateral(insured, receivedCoverage);
    }
    return receivedCoverage;
  }
}
