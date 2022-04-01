// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';

import 'hardhat/console.sol';

// Insured pool tracks how much coverage was requested to Insurer pool and how much is provided
// reconcilation will ensure the correct amount of premium is paid
abstract contract InsuredPoolBase is IInsuredPool, InsuredBalancesBase, InsuredJoinBase {
  using WadRayMath for uint256;

  uint128 private _requiredCoverage;
  uint128 private _demandedCoverage;

  uint64 private _premiumRate;

  InsuredParams private _params;

  constructor(uint256 requiredCoverage, uint64 premiumRate) {
    require((_requiredCoverage = uint128(requiredCoverage)) == requiredCoverage);
    _premiumRate = premiumRate;
  }

  function _increaseRequiredCoverage(uint256 amount) internal {
    _requiredCoverage += uint128(amount);
  }

  function internalSetInsuredParams(InsuredParams memory params) internal {
    require(params.riskWeightPct > 0);
    _params = params;
  }

  function insuredParams() public view override returns (InsuredParams memory) {
    return _params;
  }

  function internalSetServiceAccountStatus(address account, uint16 status)
    internal
    override(InsuredBalancesBase, InsuredJoinBase)
  {
    return InsuredBalancesBase.internalSetServiceAccountStatus(account, status);
  }

  function getAccountStatus(address account)
    internal
    view
    override(InsuredBalancesBase, InsuredJoinBase)
    returns (uint16)
  {
    return InsuredBalancesBase.getAccountStatus(account);
  }

  function internalIsAllowedAsHolder(uint16 status)
    internal
    view
    override(InsuredBalancesBase, InsuredJoinBase)
    returns (bool)
  {
    return InsuredJoinBase.internalIsAllowedAsHolder(status);
  }

  ///@dev When coverage demand is added, the required coverage is reduced and total demanded coverage increased
  function internalCoverageDemandAdded(
    address target,
    uint256 amount,
    uint256 premiumRate
  ) internal override {
    // console.log('internalCoverageDemandAdded', target, amount);
    _requiredCoverage = uint128(_requiredCoverage - amount);
    _demandedCoverage += uint128(amount);
    InsuredBalancesBase.internalMintForCoverage(target, amount, premiumRate);
  }

  function internalAllocateCoverageDemand(
    address target,
    uint256 amount,
    uint256 unitSize
  ) internal view override returns (uint256 amountToAdd, uint256 premiumRate) {
    target;
    unitSize;

    amountToAdd = _requiredCoverage;
    if (amountToAdd > amount) {
      amountToAdd = amount;
    }
    premiumRate = _premiumRate;
    // console.log('internalAllocateCoverageDemand', amount, _requiredCoverage, amountToAdd);
  }

  modifier onlyAdmin() virtual {
    _; // TODO
  }

  function joinPool(IJoinable pool) external onlyAdmin {
    internalJoinPool(pool);
  }

  function pushCoverageDemandTo(IInsurerPool target, uint256 amount) external onlyAdmin {
    internalPushCoverageDemandTo(target, amount);
  }

  function joinProcessed(bool accepted) external override {
    internalJoinProcessed(msg.sender, accepted);
  }

  ///@notice Reconcile with all chartered insurers
  ///@return receivedCoverage returns the total amount of received coverage
  function reconcileWithAllInsurers()
    external
    onlyAdmin
    returns (
      uint256 receivedCoverage,
      uint256 demandedCoverage,
      uint256 providedCoverage
    )
  {
    return _reconcileWithInsurers(0, type(uint256).max);
  }

  ///@notice Reconcile the coverage and premium with chartered insurers
  ///@param startIndex index to start at
  ///@param count Max amount of insurers to reconcile with
  ///@return receivedCoverage returns the total amount of received coverage
  function reconcileWithInsurers(uint256 startIndex, uint256 count)
    external
    onlyAdmin
    returns (
      uint256 receivedCoverage,
      uint256 demandedCoverage,
      uint256 providedCoverage
    )
  {
    return _reconcileWithInsurers(startIndex, count);
  }

  ///@dev Go through each insurer and reconcile with them, but don't update the rate
  function _reconcileWithInsurers(uint256 startIndex, uint256 count)
    private
    returns (
      uint256 receivedCoverage,
      uint256 demandedCoverage,
      uint256 providedCoverage
    )
  {
    address[] storage insurers = getCharteredInsurers();
    uint256 max = insurers.length;
    unchecked {
      if ((count += startIndex) > startIndex && count < max) {
        max = count;
      }
    }
    for (; startIndex < max; startIndex++) {
      (uint256 c, DemandedCoverage memory cov) = internalReconcileWithInsurer(
        IInsurerPoolDemand(insurers[startIndex]),
        false
      );
      receivedCoverage += c;
      demandedCoverage += cov.totalDemand;
      providedCoverage += cov.totalCovered;
    }
  }

  ///@dev Get the values if reconciliation were to occur with the desired Insurers
  function _reconcileWithInsurersView(uint256 startIndex, uint256 count)
    private
    view
    returns (
      uint256 receivableCoverage,
      uint256 demandedCoverage,
      uint256 providedCoverage,
      uint256 rate,
      uint256 accumulated
    )
  {
    address[] storage insurers = getCharteredInsurers();
    uint256 max = insurers.length;
    unchecked {
      if ((count += startIndex) > startIndex && count < max) {
        max = count;
      }
    }
    Balances.RateAcc memory totals = internalSyncTotals();
    for (; startIndex < max; startIndex++) {
      (uint256 c, DemandedCoverage memory cov, ) = internalReconcileWithInsurerView(
        IInsurerPoolDemand(insurers[startIndex]),
        totals
      );
      demandedCoverage += cov.totalDemand;
      providedCoverage += cov.totalCovered;
      receivableCoverage += c;
    }
    (rate, accumulated) = (totals.rate, totals.accum);
  }

  ///@dev Get the values if reconciliation were to occur with all insurers
  function receivableByReconcileWithAllInsurers()
    external
    view
    returns (
      uint256 receivableCoverage,
      uint256 demandedCoverage,
      uint256 providedCoverage,
      uint256 rate,
      uint256 accumulated
    )
  {
    return _reconcileWithInsurersView(0, type(uint256).max);
  }

  function cancelCoverage(address payoutReceiver, uint256 payoutAmount) external onlyAdmin {
    internalCancelRates();

    uint256 payoutRatio = totalCollateral();
    if (payoutRatio > 0) {
      payoutRatio = payoutAmount.rayDiv(payoutRatio);
    } else {
      require(payoutAmount == 0);
    }

    uint256 totalPayout = internalCancelInsurers(getCharteredInsurers(), payoutRatio);
    totalPayout += internalCancelInsurers(getGenericInsurers(), payoutRatio);

    require(totalPayout >= payoutAmount);
    if (payoutAmount > 0) {
      require(payoutReceiver != address(0));
      IERC20(collateral()).transfer(payoutReceiver, payoutAmount);
    }
  }

  function internalCancelInsurers(address[] storage insurers, uint256 payoutRatio)
    private
    returns (uint256 totalPayout)
  {
    IERC20 t = IERC20(collateral());

    for (uint256 i = insurers.length; i > 0; ) {
      address insurer = insurers[--i];
      t.approve(insurer, type(uint256).max);
      totalPayout += IInsurerPoolCore(insurer).cancelCoverage(payoutRatio);
      t.approve(insurer, 0);
    }
  }

  function totalCollateral() public view returns (uint256) {
    return IERC20(collateral()).balanceOf(address(this));
  }

  // function totalCoverage() public view returns(uint256 required, uint256 demanded, uint256 received) {
  //   return (_requiredCoverage, _demandedCoverage, IERC20(collateral()).balanceOf(address(this)));
  // }

  function offerCoverage(uint256 offeredAmount) external override returns (uint256 acceptedAmount, uint256 rate) {
    return internalOfferCoverage(msg.sender, offeredAmount);
  }

  function internalOfferCoverage(address account, uint256 offeredAmount)
    private
    returns (uint256 acceptedAmount, uint256 rate)
  {
    _ensureHolder(account);
    acceptedAmount = _requiredCoverage;
    if (acceptedAmount <= offeredAmount) {
      _requiredCoverage = 0;
    } else {
      _requiredCoverage = uint128(acceptedAmount - offeredAmount);
      acceptedAmount = offeredAmount;
    }
    rate = _premiumRate;
    InsuredBalancesBase.internalMintForCoverage(account, acceptedAmount, rate);
  }
}
