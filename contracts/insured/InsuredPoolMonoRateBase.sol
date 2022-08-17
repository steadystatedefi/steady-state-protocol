// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import './InsuredPoolBase.sol';

contract InsuredPoolMonoRateBase is InsuredPoolBase {
  using WadRayMath for uint256;
  using Math for uint256;

  uint96 private _requiredCoverage;
  uint96 private _demandedCoverage;
  uint64 private _premiumRate;

  constructor(IAccessController acl, address collateral_) InsuredPoolBase(acl, collateral_) {}

  event CoverageDemandUpdated(uint256 requiredCoverage, uint256 premiumRate);

  function _initializeCoverageDemand(uint256 requiredCoverage, uint256 premiumRate) internal {
    State.require(_premiumRate == 0);
    Value.require(premiumRate != 0);
    Value.require((_requiredCoverage = uint96(requiredCoverage)) == requiredCoverage);
    Value.require((_premiumRate = uint64(premiumRate)) == premiumRate);
    emit CoverageDemandUpdated(requiredCoverage, premiumRate);
  }

  function internalAddRequiredCoverage(uint256 amount) internal {
    _requiredCoverage += amount.asUint96();
    emit CoverageDemandUpdated(_requiredCoverage + _demandedCoverage, _premiumRate);
  }

  /// @dev When coverage demand is added, the required coverage is reduced and total demanded coverage increased
  /// @dev Mints to the appropriate insurer
  // slither-disable-next-line calls-loop
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

  function rateBands() external view override returns (InsuredRateBand[] memory bands, uint256) {
    if (_premiumRate > 0) {
      bands = new InsuredRateBand[](1);
      bands[0].premiumRate = _premiumRate;
      bands[0].coverageDemand = _requiredCoverage + _demandedCoverage;
    }
    return (bands, 1);
  }

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

  function cancelAllCoverageDemand() external onlyGovernorOr(AccessFlags.INSURED_OPS) returns (uint256 cancelledDemand) {
    address[] storage targets = getCharteredInsurers();
    for (uint256 i = targets.length; i > 0; ) {
      i--;
      cancelledDemand += _cancelDemand(targets[i], type(uint256).max);
    }
  }

  event CoverageDemandCancelled(address indexed insurer, uint256 requested, uint256 cancelled);

  // slither-disable-next-line calls-loop
  function _cancelDemand(address insurer, uint256 requestedAmount) private returns (uint256 totalPayout) {
    uint256 unitSize = ICancellableCoverageDemand(insurer).coverageUnitSize();
    uint256 unitCount = requestedAmount.divUp(unitSize);
    if (unitCount > 0) {
      unitCount = ICancellableCoverageDemand(insurer).cancelCoverageDemand(address(this), unitCount, 0);
    }

    if (unitCount > 0) {
      totalPayout = unitCount * unitSize;

      _demandedCoverage = uint96(_demandedCoverage - totalPayout);
      Value.require((_requiredCoverage += uint96(totalPayout)) >= totalPayout);
      internalBurnForDemandedCoverage(insurer, totalPayout.wadMul(_premiumRate));
    }

    emit CoverageDemandCancelled(insurer, requestedAmount, totalPayout);
  }
}
