// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../libraries/Balances.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolBase.sol';
import './InsurerJoinBase.sol';

// Handles Insured pool functions, adding/cancelling demand
abstract contract WeightedPoolExtension is ICoverageDistributor, WeightedPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  /// @notice Coverage Unit Size is the minimum amount of coverage that can be demanded/provided
  /// @return The coverage unit size
  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  /// @inheritdoc ICoverageDistributor
  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore,
    uint256 loopLimit
  ) external override onlyActiveInsured returns (uint256 addedCount) {
    AddCoverageDemandParams memory params;
    params.insured = msg.sender;
    Arithmetic.require(premiumRate == (params.premiumRate = uint40(premiumRate)));
    params.loopLimit = defaultLoopLimit(LoopLimitType.AddCoverageDemand, loopLimit);
    //    params.hasMore = hasMore;
    Arithmetic.require(unitCount <= type(uint64).max);

    addedCount = unitCount - super.internalAddCoverageDemand(uint64(unitCount), params);
    //If there was excess coverage before adding this demand, immediately assign it
    if (_excessCoverage > 0 && internalCanAddCoverage()) {
      // avoid addCoverage code to be duplicated within WeightedPoolExtension to reduce contract size
      WeightedPoolBase(address(this)).pushCoverageExcess();
    }
    return addedCount;
  }

  function _onlyActiveInsuredOrOps(address insured) private view {
    if (insured != msg.sender) {
      _onlyGovernorOr(AccessFlags.INSURER_OPS);
    }
    _onlyActiveInsured(insured);
  }

  modifier onlyActiveInsuredOrOps(address insured) {
    _onlyActiveInsuredOrOps(insured);
    _;
  }

  function cancelCoverageDemand(
    address insured,
    uint256 unitCount,
    uint256 loopLimit
  ) external override onlyActiveInsuredOrOps(insured) returns (uint256 cancelledUnits) {
    CancelCoverageDemandParams memory params;
    params.insured = insured;
    params.loopLimit = defaultLoopLimit(LoopLimitType.CancelCoverageDemand, loopLimit);

    if (unitCount > type(uint64).max) {
      unitCount = type(uint64).max;
    }
    return internalCancelCoverageDemand(uint64(unitCount), params);
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

    // NB! when protocol is not fully covered, then there will be a discrepancy between the coverage provided ad-hoc
    // and the actual amount of protocol tokens made available during last sync
    // so this is a sanity check - insurance must be sync'ed before cancellation
    // otherwise there will be premium without actual supply of protocol tokens

    payoutValue = providedCoverage.rayMul(payoutRatio);

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

  /// @inheritdoc ICoverageDistributor
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

  /// @inheritdoc ICoverageDistributor
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

    if (address(_premiumDistributor) != address(0)) {
      _premiumDistributor.premiumAllocationUpdated(insured, coverage.totalPremium, params.receivedPremium, coverage.premiumRate);
    }

    return (params.receivedCoverage, receivedCollateral, coverage);
  }

  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory coverage
  ) internal virtual returns (uint256);
}
