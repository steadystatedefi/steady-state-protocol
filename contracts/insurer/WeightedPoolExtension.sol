// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../libraries/Balances.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolBase.sol';
import './InsurerJoinBase.sol';

// Handles Insured pool functions, adding/cancelling demand
abstract contract WeightedPoolExtension is IReceivableCoverage, WeightedPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  /// @notice Coverage Unit Size is the minimum amount of coverage that can be demanded/provided
  /// @return The coverage unit size
  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  function cancelCoverage(address insured, uint256 payoutRatio)
    external
    override
    onlyActiveInsuredOrOps(insured)
    onlyUnpaused
    returns (uint256 payoutValue)
  {
    bool enforcedCancel = msg.sender != insured;
    if (payoutRatio > 0) {
      payoutRatio = internalVerifyPayoutRatio(insured, payoutRatio, enforcedCancel);
    }
    (payoutValue, ) = internalCancelCoverage(insured, payoutRatio, enforcedCancel);
  }

  /// @dev Cancel all coverage for the insured and payout
  /// @param insured The address of the insured to cancel
  /// @param payoutRatio The RAY ratio of how much of provided coverage should be paid out
  /// @return payoutValue The effective amount of coverage paid out to the insured (includes all )
  function internalCancelCoverage(
    address insured,
    uint256 payoutRatio,
    bool enforcedCancel
  ) private returns (uint256 payoutValue, uint256 deductedValue) {
    (DemandedCoverage memory coverage, uint256 excessCoverage, uint256 providedCoverage, uint256 receivableCoverage, uint256 receivedPremium) = super
      .internalCancelCoverage(insured);
    // NB! receivableCoverage was not yet received by the insured, it was found during the cancallation
    // and caller relies on a coverage provided earlier

    payoutValue = providedCoverage.rayMul(payoutRatio);

    // NB! when protocol is not fully covered, then there will be a discrepancy between the coverage provided ad-hoc
    // and the actual amount of protocol tokens made available during last sync
    // so this is a sanity check - insurance must be sync'ed before cancellation
    // otherwise there will be premium without actual supply of protocol tokens
    require(
      enforcedCancel || ((receivableCoverage <= providedCoverage >> 16) && (receivableCoverage + payoutValue <= providedCoverage)),
      'must be reconciled'
    );

    uint256 premiumDebt = address(_premiumDistributor) == address(0)
      ? 0
      : _premiumDistributor.premiumAllocationFinished(insured, coverage.totalPremium, receivedPremium);

    internalSetStatus(insured, MemberStatus.Declined);

    if (premiumDebt > 0) {
      unchecked {
        if (premiumDebt >= payoutValue) {
          deductedValue = payoutValue;
          premiumDebt -= payoutValue;
          payoutValue = 0;
        } else {
          deductedValue = premiumDebt;
          payoutValue -= premiumDebt;
          premiumDebt = 0;
        }
      }
    }

    payoutValue = internalTransferCancelledCoverage(
      insured,
      payoutValue,
      providedCoverage - receivableCoverage,
      excessCoverage + receivableCoverage,
      premiumDebt
    );
  }

  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) internal virtual returns (uint256);

  /// @inheritdoc IReceivableCoverage
  function receivableDemandedCoverage(address insured, uint256 loopLimit)
    external
    view
    override
    returns (uint256 receivableCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = defaultLoopLimit(LoopLimitType.ReceivableDemandedCoverage, loopLimit);

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  /// @inheritdoc IReceivableCoverage
  function receiveDemandedCoverage(address insured, uint256 loopLimit)
    external
    override
    onlyActiveInsured
    onlyUnpaused
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
      DemandedCoverage memory coverage
    )
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = defaultLoopLimit(LoopLimitType.ReceiveDemandedCoverage, loopLimit);

    coverage = internalUpdateCoveredDemand(params);
    receivedCollateral = internalTransferDemandedCoverage(insured, params.receivedCoverage, coverage);

    if (coverage.premiumRate != 0) {
      if (address(_premiumDistributor) != address(0)) {
        _premiumDistributor.premiumAllocationUpdated(insured, coverage.totalPremium, params.receivedPremium, coverage.premiumRate);
      }
    } else {
      Sanity.require(coverage.totalPremium == 0);
    }

    return (params.receivedCoverage, receivedCollateral, coverage);
  }

  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory coverage
  ) internal virtual returns (uint256);

  function getPendingAdjustments()
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

  function applyPendingAdjustments() external {
    internalApplyAdjustmentsToTotals();
  }

  function getTotals(uint256 loopLimit) external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals(loopLimit == 0 ? type(uint256).max : loopLimit);
  }

  function weightedParams() external view returns (WeightedPoolParams memory) {
    return _params;
  }

  function dumpBatches() external view returns (Dump memory) {
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
}
