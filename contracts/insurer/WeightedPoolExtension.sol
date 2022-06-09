// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IJoinHandler.sol';
import './WeightedPoolStorage.sol';
import './InsurerJoinBase.sol';

// Handles Insured pool functions, adding/cancelling demand
abstract contract WeightedPoolExtension is InsurerJoinBase, IInsurerPoolDemand, WeightedPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(uint256 unitSize) InsurancePoolBase(address(0)) WeightedRoundsBase(unitSize) {}

  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external override {
    require(msg.sender == insured); // TODO or admin?
    internalRequestJoin(insured);
  }

  /// @inheritdoc IInsurerPoolBase
  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  /// @notice Coverage Unit Size is the minimum amount of coverage that can be demanded/provided
  /// @return The coverage unit size
  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  /// @inheritdoc IInsurerPoolDemand
  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external override onlyActiveInsured returns (uint256 addedCount) {
    AddCoverageDemandParams memory params;
    params.insured = msg.sender;
    require(premiumRate == (params.premiumRate = uint40(premiumRate)));
    params.loopLimit = ~params.loopLimit;
    hasMore;
    require(unitCount <= type(uint64).max);

    addedCount = unitCount - super.internalAddCoverageDemand(uint64(unitCount), params);
    //If there was excess coverage before adding this demand, immediately assign it
    if (_excessCoverage > 0 && internalCanAddCoverage()) {
      // avoid addCoverage code to be duplicated within WeightedPoolExtension to reduce contract size
      IExcessHandler(address(this)).pushCoverageExcess();
    }
    return addedCount;
  }

  /// @inheritdoc IInsurerPoolDemand
  function cancelCoverageDemand(uint256 unitCount) external override onlyActiveInsured returns (uint256 cancelledUnits) {
    CancelCoverageDemandParams memory params;
    params.insured = msg.sender;
    params.loopLimit = ~params.loopLimit;

    if (unitCount > type(uint64).max) {
      unitCount = type(uint64).max;
    }

    // TODO event
    return internalCancelCoverageDemand(uint64(unitCount), params);
  }

  /// @inheritdoc IInsurerPoolBase
  function cancelCoverage(uint256 payoutRatio) external override onlyActiveInsured returns (uint256 payoutValue) {
    return internalCancelCoverage(msg.sender, payoutRatio);
  }

  /// @dev Cancel all coverage for the insured and payout
  /// @param insured The address of the insured to cancel
  /// @param payoutRatio The RAY ratio of how much of provided coverage should be paid out
  /// @return payoutValue The amount of coverage paid out to the insured
  function internalCancelCoverage(address insured, uint256 payoutRatio) private onlyActiveInsured returns (uint256 payoutValue) {
    (DemandedCoverage memory coverage, uint256 excessCoverage, uint256 providedCoverage, uint256 receivableCoverage) = super.internalCancelCoverage(
      insured
    );
    coverage;
    // receivableCoverage was not yet received by the insured, it was found during the cancallation
    // and caller relies on a coverage provided earlier

    payoutValue = providedCoverage.rayMul(payoutRatio);

    /* TODO Apply MCD
      actual providedCoverage is tracked
      move transferCollateralFrom to the other side and do calcs there?
    */

    // NB! when protocol is not fully covered, then there will be a discrepancy between the coverage provided ad-hoc
    // and the actual amount of protocol tokens made available during last sync
    // so this is a sanity check - insurance must be sync'ed before cancellation
    // otherwise there will be premium without actual supply of protocol tokens

    require((receivableCoverage <= providedCoverage >> 16) && (receivableCoverage + payoutValue <= providedCoverage), 'must be reconciled');
    internalSetStatus(insured, InsuredStatus.Declined);

    return internalTransferCancelledCoverage(insured, payoutValue, excessCoverage, providedCoverage, providedCoverage - receivableCoverage);
  }

  /* payout, excess, providedCoverage, receivedCoverage

  PERP: transferCollateralFrom(insured, address(this), receivedCoverage - payout);

  IMPERP: transferCollateralFrom(insured, address(this), givenCoverage - payout); or
  IMPERP: transferCollateralTo(insured, min(payout, providedCoverage*(1-CCD)) - givenCoverage); or

  */
  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 excessCoverage,
    uint256 providedCoverage,
    uint256 receivedCoverage
  ) internal virtual returns (uint256);

  /// @inheritdoc IInsurerPoolDemand
  function receivableDemandedCoverage(address insured) external view override returns (uint256 receivedCoverage, DemandedCoverage memory coverage) {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  /// @inheritdoc IInsurerPoolDemand
  function receiveDemandedCoverage(address insured)
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
    params.loopLimit = ~params.loopLimit;

    coverage = internalUpdateCoveredDemand(params);
    receivedCollateral = internalTransferDemandedCoverage(insured, params.receivedCoverage, coverage);

    return (params.receivedCoverage, receivedCollateral, coverage);
  }

  /* TODO apply MCD
          keep track of MCD-deducted amount 
          compare with maxDrawdown
          withheld or give out more
      */
  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory coverage
  ) internal virtual returns (uint256);

  /// @dev Prepare for an insured pool to join by setting the parameters
  function internalPrepareJoin(address insured) internal override {
    WeightedPoolParams memory params = _params;
    InsuredParams memory insuredParams = IInsuredPool(insured).insuredParams();

    uint256 maxShare = uint256(insuredParams.riskWeightPct).percentDiv(params.riskWeightTarget);
    if (maxShare >= params.maxInsuredShare) {
      maxShare = params.maxInsuredShare;
    } else if (maxShare < params.minInsuredShare) {
      maxShare = params.minInsuredShare;
    }

    super.internalSetInsuredParams(insured, Rounds.InsuredParams({minUnits: insuredParams.minUnitsPerInsurer, maxShare: uint16(maxShare)}));
  }

  function internalInitiateJoin(address insured) internal override returns (InsuredStatus) {
    if (_joinHandler == address(0)) return InsuredStatus.Joining;
    if (_joinHandler == address(this)) return InsuredStatus.Accepted;
    return IJoinHandler(_joinHandler).handleJoinRequest(insured);
  }

  ///@dev Return if an account has a balance or premium earned
  function internalIsInvestor(address account) internal view override(InsurerJoinBase, WeightedPoolStorage) returns (bool) {
    return WeightedPoolStorage.internalIsInvestor(account);
  }

  function internalGetStatus(address account) internal view override(InsurerJoinBase, WeightedPoolStorage) returns (InsuredStatus) {
    return WeightedPoolStorage.internalGetStatus(account);
  }

  function internalSetStatus(address account, InsuredStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }
}
