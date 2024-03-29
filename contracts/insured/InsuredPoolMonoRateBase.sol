// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import './InsuredPoolBase.sol';

/// @dev An implementation of an insurance policy which pays same premium rate per unit for any amount of coverage, i.e. has only one rate band.
contract InsuredPoolMonoRateBase is InsuredPoolBase {
  using WadRayMath for uint256;
  using Math for uint256;

  uint96 private _requiredCoverage;
  uint96 private _demandedCoverage;
  uint64 private _premiumRate;

  constructor(IAccessController acl, address collateral_) InsuredPoolBase(acl, collateral_) {}

  event CoverageDemandUpdated(uint256 requiredCoverage, uint256 demandedCoverage, uint256 premiumRate);

  /// @dev Can change premium rate only when demanded coverage is zero.
  function _initializeCoverageDemand(uint256 requiredCoverage, uint256 premiumRate) internal {
    Value.require(premiumRate != 0);
    if (_premiumRate != premiumRate) {
      State.require(_demandedCoverage == 0);
      Arithmetic.require((_premiumRate = uint64(premiumRate)) == premiumRate);
    }
    Arithmetic.require((_requiredCoverage = uint96(requiredCoverage)) == requiredCoverage);
    emit CoverageDemandUpdated(requiredCoverage, _demandedCoverage, premiumRate);
  }

  function internalAddRequiredCoverage(uint256 amount) internal {
    Arithmetic.require((_requiredCoverage += uint96(amount)) >= amount);
    emit CoverageDemandUpdated(_requiredCoverage, _demandedCoverage, _premiumRate);
  }

  /// @dev When coverage demand is added to an insurer, the required coverage is reduced and total demanded coverage increased
  /// @dev Mints to the appropriate insurer
  // slither-disable-next-line costly-loop
  function internalCoverageDemandAdded(
    address target,
    uint256 amount,
    uint256 premiumRate
  ) internal override {
    _requiredCoverage = uint96(_requiredCoverage - amount);
    _demandedCoverage += uint96(amount);
    InsuredBalancesBase.internalMintForDemandedCoverage(target, amount.wadMul(premiumRate));
  }

  function internalAllocateCoverageDemand(
    address,
    uint256,
    uint256 maxAmount,
    uint256
  ) internal view override returns (uint256 amountToAdd, uint256 premiumRate) {
    amountToAdd = _requiredCoverage;
    if (amountToAdd > maxAmount) {
      amountToAdd = maxAmount;
    }
    premiumRate = _premiumRate;
  }

  /// @dev Sets required demand of coverage and premium rate for coverage.
  /// @param requiredCoverage which can be given (pushed) to insurers.
  /// @param premiumRate can only be changed when demanded coverage is zero. When an application is approved, it must be >= basePremiumRate.
  function setCoverageDemand(uint256 requiredCoverage, uint256 premiumRate) external onlyGovernor {
    if (internalHasAppliedApplication()) {
      IApprovalCatalog.ApprovedPolicy memory ap = internalGetApprovedPolicy();
      Value.require(premiumRate >= ap.basePremiumRate);
    }
    _initializeCoverageDemand(requiredCoverage, premiumRate);
  }

  function internalOfferCoverage(address account, uint256 offeredAmount) internal override returns (uint256 acceptedAmount, uint256 rate) {
    _ensureHolder(account);
    acceptedAmount = _requiredCoverage;
    if (acceptedAmount <= offeredAmount) {
      _requiredCoverage = 0;
    } else {
      _requiredCoverage = uint96(acceptedAmount - offeredAmount);
      acceptedAmount = offeredAmount;
    }
    rate = _premiumRate;
    InsuredBalancesBase.internalMintForDemandedCoverage(account, acceptedAmount.wadMul(rate));
  }

  /// @inheritdoc IInsuredPool
  function rateBands() external view override returns (InsuredRateBand[] memory bands, uint256) {
    uint256 v = _premiumRate;
    if (v > 0) {
      bands = new InsuredRateBand[](1);
      bands[0].premiumRate = v;
      bands[0].assignedDemand = v = _demandedCoverage;
      bands[0].coverageDemand = _requiredCoverage + v;
    }
    return (bands, 1);
  }

  /// @dev Cancels uncovered demand.
  /// @dev Actual cancelled demand can be less than requested (e.g. covered already) or more (due to insurer's internal optimizations).
  /// @param targets is a list of insurers to cancel demand, which was pushed earlier.
  /// @param amounts is a list max demand to be cancelled.
  /// @return cancelledDemand summed up by all targets.
  function cancelCoverageDemand(address[] calldata targets, uint256[] calldata amounts)
    external
    onlyGovernorOr(AccessFlags.INSURED_OPS)
    returns (uint256 cancelledDemand)
  {
    Value.require(targets.length == amounts.length);
    for (uint256 i = 0; i < targets.length; i++) {
      cancelledDemand += _cancelDemand(targets[i], amounts[i]);
    }
  }

  /// @dev Cancels all uncovered demand.
  /// @return cancelledDemand summed up by all targets.
  function cancelAllCoverageDemand() external onlyGovernorOr(AccessFlags.INSURED_OPS) returns (uint256 cancelledDemand) {
    address[] storage targets = getCharteredInsurers();
    for (uint256 i = targets.length; i > 0; ) {
      i--;
      cancelledDemand += _cancelDemand(targets[i], type(uint256).max);
    }
  }

  event CoverageDemandCancelled(address indexed insurer, uint256 requested, uint256 cancelled);

  // slither-disable-next-line calls-loop,costly-loop
  function _cancelDemand(address insurer, uint256 requestedAmount) private returns (uint256 totalPayout) {
    uint256 unitSize = IDemandableCoverage(insurer).coverageUnitSize();
    uint256 unitCount = requestedAmount == type(uint256).max ? requestedAmount : requestedAmount.divUp(unitSize);
    if (unitCount > 0) {
      uint256[] memory canceledBands;
      (unitCount, canceledBands) = IDemandableCoverage(insurer).cancelCoverageDemand(address(this), unitCount, 0);
      Sanity.require(canceledBands.length <= 1);
    }

    if (unitCount > 0) {
      totalPayout = unitCount * unitSize;

      _demandedCoverage = uint96(_demandedCoverage - totalPayout);
      Arithmetic.require((_requiredCoverage += uint96(totalPayout)) >= totalPayout);
      internalBurnForDemandedCoverage(insurer, totalPayout.wadMul(_premiumRate));
    }

    emit CoverageDemandCancelled(insurer, requestedAmount, totalPayout);
  }
}
