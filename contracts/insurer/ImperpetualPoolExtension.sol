// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './WeightedPoolExtension.sol';
import './ImperpetualPoolBase.sol';

/// @dev NB! MUST HAVE NO STORAGE
/// @dev This is a a portion of implementation of an insurer where coverage can be partially taken out (i.e. supports drawdown).
/// @dev This portion contains logic to handle coverage-related operations of insureds, except for add/cancel of demand.
contract ImperpetualPoolExtension is WeightedPoolExtension {
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
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) internal override returns (uint256) {
    return ImperpetualPoolBase(address(this)).updateCoverageOnCancel(insured, payoutValue, advanceValue, recoveredValue, premiumDebt);
    // ^^ this call avoids code to be duplicated within PoolExtension to reduce contract size
  }

  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory coverage
  ) internal override returns (uint256) {
    if (receivedCoverage > 0) {
      return ImperpetualPoolBase(address(this)).updateCoverageOnReconcile(insured, receivedCoverage, coverage.totalCovered);
      // ^^ this call avoids code to be duplicated within PoolExtension to reduce contract size
    }
    return receivedCoverage;
  }
}
