// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../libraries/Balances.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolBase.sol';
import './InsurerJoinBase.sol';

// Handles Insured pool functions, adding/cancelling demand
abstract contract WeightedPoolExtension is ICoverageDistributor, WeightedPoolStorage, InsurerJoinBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(uint256 unitSize) Collateralized(address(0)) WeightedRoundsBase(unitSize) {}

  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external override {
    require(msg.sender == insured); // TODO or admin?
    internalRequestJoin(insured);
  }

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
    require(premiumRate == (params.premiumRate = uint40(premiumRate)));
    params.loopLimit = defaultLoopLimit(LoopLimitType.AddCoverageDemand, loopLimit);
    hasMore;
    require(unitCount <= type(uint64).max);

    addedCount = unitCount - super.internalAddCoverageDemand(uint64(unitCount), params);
    //If there was excess coverage before adding this demand, immediately assign it
    if (_excessCoverage > 0 && internalCanAddCoverage()) {
      // avoid addCoverage code to be duplicated within WeightedPoolExtension to reduce contract size
      WeightedPoolBase(address(this)).pushCoverageExcess();
    }
    return addedCount;
  }

  function cancelCoverageDemand(
    address insured,
    uint256 unitCount,
    uint256 loopLimit
  ) external override returns (uint256 cancelledUnits) {
    /*
    ATTN! Access check for msg.sender for this method is done by WeightedPoolBase.cancelCoverageDemand    
     */
    _onlyActiveInsured(insured);
    CancelCoverageDemandParams memory params;
    params.insured = insured;
    params.loopLimit = defaultLoopLimit(LoopLimitType.CancelCoverageDemand, loopLimit);

    if (unitCount > type(uint64).max) {
      unitCount = type(uint64).max;
    }

    // TODO event
    return internalCancelCoverageDemand(uint64(unitCount), params);
  }

  function cancelCoverage(address insured, uint256 payoutRatio) external override returns (uint256 payoutValue) {
    /*
    ATTN! Access check for msg.sender for this method is done by WeightedPoolBase.cancelCoverage
     */
    _onlyActiveInsured(insured);
    return internalCancelCoverage(insured, payoutRatio);
  }

  /// @dev Cancel all coverage for the insured and payout
  /// @param insured The address of the insured to cancel
  /// @param payoutRatio The RAY ratio of how much of provided coverage should be paid out
  /// @return payoutValue The amount of coverage paid out to the insured
  function internalCancelCoverage(address insured, uint256 payoutRatio) private returns (uint256 payoutValue) {
    (DemandedCoverage memory coverage, uint256 excessCoverage, uint256 providedCoverage, uint256 receivableCoverage, uint256 receivedPremium) = super
      .internalCancelCoverage(insured);
    // NB! receivableCoverage was not yet received by the insured, it was found during the cancallation
    // and caller relies on a coverage provided earlier

    // NB! when protocol is not fully covered, then there will be a discrepancy between the coverage provided ad-hoc
    // and the actual amount of protocol tokens made available during last sync
    // so this is a sanity check - insurance must be sync'ed before cancellation
    // otherwise there will be premium without actual supply of protocol tokens

    payoutValue = providedCoverage.rayMul(payoutRatio);

    require((receivableCoverage <= providedCoverage >> 16) && (receivableCoverage + payoutValue <= providedCoverage), 'must be reconciled');

    if (address(_premiumDistributor) != address(0)) {
      uint256 premiumDebt = _premiumDistributor.premiumAllocationFinished(insured, coverage.totalPremium, receivedPremium);
      unchecked {
        payoutValue = payoutValue <= premiumDebt ? 0 : payoutValue - premiumDebt;
      }
    }

    internalSetStatus(insured, InsuredStatus.Declined);

    return internalTransferCancelledCoverage(insured, payoutValue, excessCoverage, providedCoverage, providedCoverage - receivableCoverage);
  }

  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 excessCoverage,
    uint256 providedCoverage,
    uint256 receivedCoverage
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

  event DemandedCoverageReceived(address insured, uint256 receivedCoverage, uint256 receivedCollateral);

  /// @inheritdoc ICoverageDistributor
  function receiveDemandedCoverage(address insured, uint256 loopLimit)
    external
    override
    onlyActiveInsured
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

    emit DemandedCoverageReceived(insured, params.receivedCoverage, receivedCollateral);
    return (params.receivedCoverage, receivedCollateral, coverage);
  }

  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory coverage
  ) internal virtual returns (uint256);

  /// @dev Prepare for an insured pool to join by setting the parameters
  function internalPrepareJoin(address insured) internal override {
    InsuredParams memory insuredParams = IInsuredPool(insured).insuredParams();

    uint256 maxShare = uint256(insuredParams.riskWeightPct).percentDiv(_params.riskWeightTarget);
    uint256 v;
    if (maxShare >= (v = _params.maxInsuredShare)) {
      maxShare = v;
    } else if (maxShare < (v = _params.minInsuredShare)) {
      maxShare = v;
    }

    super.internalSetInsuredParams(insured, Rounds.InsuredParams({minUnits: insuredParams.minUnitsPerInsurer, maxShare: uint16(maxShare)}));
  }

  function internalInitiateJoin(address insured) internal override returns (InsuredStatus) {
    IJoinHandler jh = governorContract();
    return address(jh) == address(0) ? InsuredStatus.Joining : jh.handleJoinRequest(insured);
  }

  ///@dev Return if an account has a balance or premium earned
  function internalIsInvestor(address account) internal view override(InsurerJoinBase, WeightedPoolStorage) returns (bool) {
    return WeightedPoolStorage.internalIsInvestor(account);
  }

  function internalGetStatus(address account) internal view override(InsurerJoinBase, WeightedPoolConfig) returns (InsuredStatus) {
    return WeightedPoolConfig.internalGetStatus(account);
  }

  function internalSetStatus(address account, InsuredStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }

  function internalAfterJoinOrLeave(address insured, InsuredStatus status) internal override {
    if (address(_premiumDistributor) != address(0)) {
      _premiumDistributor.registerPremiumSource(insured, status == InsuredStatus.Accepted);
    }
  }
}
