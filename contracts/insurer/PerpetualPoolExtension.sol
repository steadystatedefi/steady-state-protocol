// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './WeightedPoolExtension.sol';
import './PerpetualPoolBase.sol';

/// @dev NB! MUST HAVE NO STORAGE
/// @dev This is a a portion of implementation of prepetual-bond-style insurer (coverage can not be taken out).
/// @dev This portion contains logic to handle coverage-related operations of insureds, except for add/cancel of demand.
contract PerpetualPoolExtension is WeightedPoolExtension {
  using Math for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedPoolConfig(acl, unitSize, collateral_) {}

  /// @inheritdoc WeightedPoolExtension
  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) internal override returns (uint256) {
    uint256 givenOutValue = subBalanceOfCollateral(insured);
    Sanity.require(givenOutValue == advanceValue);

    (payoutValue, premiumDebt) = payoutValue.boundedXSub(premiumDebt);
    recoveredValue += advanceValue.boundedSub(payoutValue);

    closeCollateralSubBalance(insured, payoutValue);

    // This call avoids code to be duplicated within the PoolExtension to reduce contract size
    PerpetualPoolBase(address(this)).updateCoverageOnCancel(payoutValue + premiumDebt, recoveredValue, 0);

    return payoutValue;
  }

  /// @inheritdoc WeightedPoolExtension
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
