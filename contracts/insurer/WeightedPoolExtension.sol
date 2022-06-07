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
contract WeightedPoolExtension is InsurerJoinBase, IInsurerPoolDemand, WeightedPoolStorage {
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

  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  ///@notice Add coverage demand to the pool, called by insured
  ///@param unitCount The number of units to demand
  ///@param premiumRate The rate that will be paid on this coverage
  ///@param hasMore Whether the Insured has more demand it would like to request after this
  ///@return addedCount The amount of coverage demand added
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

  ///@notice Cancel coverage that has been demanded, but not filled yet
  ///@param unitCount The number of units that wishes to be cancelled
  ///@return cancelledUnits The amount of units that were cancelled
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

  function cancelCoverage(uint256 payoutRatio) external override onlyActiveInsured returns (uint256 payoutValue) {
    return internalCancelCoverage(msg.sender, payoutRatio);
  }

  function internalCancelCoverage(address insured, uint256 payoutRatio) private onlyActiveInsured returns (uint256 payoutValue) {
    (DemandedCoverage memory coverage, uint256 excessCoverage, uint256 providedCoverage, uint256 receivableCoverage) = super.internalCancelCoverage(
      insured
    );

    // receivableCoverage was not yet received by the insured, it was found during the cancallation
    // and caller relies on a coverage provided earlier
    providedCoverage -= receivableCoverage;

    // NB! when protocol is not fully covered, then there will be a discrepancy between the coverage provided ad-hoc
    // and the actual amount of protocol tokens made available during last sync
    coverage;
    // so this is a sanity check - insurance must be sync'ed before cancellation
    // otherwise there will be premium without actual supply of protocol tokens
    require(receivableCoverage <= (providedCoverage >> 4), 'coverage must be received before cancellation');
    internalSetStatus(insured, InsuredStatus.Declined);

    payoutValue = providedCoverage.rayMul(payoutRatio);

    providedCoverage -= payoutValue;
    if (providedCoverage > 0) {
      // take back the unused provided coverage
      transferCollateralFrom(insured, address(this), providedCoverage);
    }
    // this call is to consider / reinvest the released funds
    IExcessHandler(address(this)).updateCoverageOnCancel(payoutValue, excessCoverage + providedCoverage + receivableCoverage);
    // ^^ avoids code to be duplicated within WeightedPoolExtension to reduce contract size
  }

  ///@notice Get the amount of coverage demanded and filled, and the total premium rate and premium charged
  ///@param insured The insured pool
  ///@return receivedCoverage The amount of $CC that has been covered
  ///@return coverage All the details relating to the coverage, demand and premium
  function receivableDemandedCoverage(address insured) external view override returns (uint256 receivedCoverage, DemandedCoverage memory coverage) {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  ///@notice Transfer the amount of coverage that been filled to the insured
  ///TODO
  function receiveDemandedCoverage(address insured)
    external
    override
    onlyActiveInsured
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    coverage = internalUpdateCoveredDemand(params);

    if (params.receivedCoverage > 0) {
      transferCollateral(insured, params.receivedCoverage);
    }

    return (params.receivedCoverage, coverage);
  }

  ///@dev Prepare for an insured pool to join by setting the parameters
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
