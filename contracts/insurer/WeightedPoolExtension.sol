// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsuredPool.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolBase.sol';
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
    // TODO access control
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
      WeightedPoolBase(address(this)).pushCoverageExcess();
    }
    return addedCount;
  }

  ///@notice Cancel coverage that has been demanded, but not filled yet
  ///@param unitCount The number of units that wishes to be cancelled
  ///@return cancelledUnits The amount of units that were cancelled
  function cancelCoverageDemand(uint256 unitCount)
    external
    override
    onlyActiveInsured
    returns (uint256 cancelledUnits)
  {
    CancelCoverageDemandParams memory params;
    params.insured = msg.sender;
    params.loopLimit = ~params.loopLimit;

    if (unitCount > type(uint64).max) {
      unitCount = type(uint64).max;
    }

    // TODO event
    return internalCancelCoverageDemand(uint64(unitCount), params);
  }

  function cancelCoverage(uint256 paidoutCoverage) external override onlyActiveInsured {
    (bool ok, uint256 excess, uint256 coverage) = internalCancelCoverage(msg.sender);
    if (ok) {
      coverage -= paidoutCoverage;
      if (coverage > 0) {
        transferCollateralFrom(msg.sender, address(this), coverage);
      }
      // avoid code to be duplicated within WeightedPoolExtension to reduce contract size
      WeightedPoolBase(address(this)).updateCoverageOnCancel(paidoutCoverage, excess + coverage);
    }
  }

  ///@notice Get the amount of coverage demanded and filled, and the total premium rate and premium charged
  ///@param insured The insured pool
  ///@return receivedCoverage The amount of $CC that has been covered
  ///@return coverage All the details relating to the coverage, demand and premium
  function receivableDemandedCoverage(address insured)
    external
    view
    override
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
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
      transferCollateral(
        insured,
        params.receivedCoverage,
        abi.encodeWithSelector(DInsuredPoolTransfer.addCoverageByInsurer.selector)
      );
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

    super.internalSetInsuredParams(
      insured,
      Rounds.InsuredParams({minUnits: insuredParams.minUnitsPerInsurer, maxShare: uint16(maxShare)})
    );
  }

  function internalInitiateJoin(address insured) internal override returns (InsuredStatus) {
    if (_joinHandler == address(0)) return InsuredStatus.Joining;
    if (_joinHandler == address(this)) return InsuredStatus.Accepted;
    return IJoinHandler(_joinHandler).handleJoinRequest(insured);
  }

  ///@dev Return if an account has a balance or premium earned
  function internalIsInvestor(address account)
    internal
    view
    override(InsurerJoinBase, WeightedPoolStorage)
    returns (bool)
  {
    return WeightedPoolStorage.internalIsInvestor(account);
  }

  function internalGetStatus(address account)
    internal
    view
    override(InsurerJoinBase, WeightedPoolStorage)
    returns (InsuredStatus)
  {
    return WeightedPoolStorage.internalGetStatus(account);
  }

  function internalSetStatus(address account, InsuredStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }

  function onTransferReceived(
    address,
    address,
    uint256,
    bytes memory
  ) external pure override returns (bytes4) {
    revert();
  }
}
