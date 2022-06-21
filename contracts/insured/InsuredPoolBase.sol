// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';
import './PremiumCollectorBase.sol';

import 'hardhat/console.sol';

/// @title Insured Pool Base
/// @notice The base pool that tracks how much coverage is requested, provided and paid
/// @dev Reconcilation must be called for the most accurate information
abstract contract InsuredPoolBase is IInsuredPool, InsuredBalancesBase, InsuredJoinBase, PremiumCollectorBase {
  using WadRayMath for uint256;

  uint128 private _requiredCoverage;
  uint128 private _demandedCoverage;

  uint64 private _premiumRate;

  InsuredParams private _params;

  constructor(uint256 requiredCoverage, uint64 premiumRate) {
    require((_requiredCoverage = uint128(requiredCoverage)) == requiredCoverage);
    _premiumRate = premiumRate;
  }

  function collateral() public view override(ICollateralized, InsurancePoolBase, PremiumCollectorBase) returns (address) {
    return InsurancePoolBase.collateral();
  }

  function _increaseRequiredCoverage(uint256 amount) internal {
    _requiredCoverage += uint128(amount);
  }

  function internalSetInsuredParams(InsuredParams memory params) internal {
    require(params.riskWeightPct > 0);
    _params = params;
  }

  /// @inheritdoc IInsuredPool
  function insuredParams() public view override returns (InsuredParams memory) {
    return _params;
  }

  function internalSetServiceAccountStatus(address account, uint16 status) internal override(InsuredBalancesBase, InsuredJoinBase) {
    return InsuredBalancesBase.internalSetServiceAccountStatus(account, status);
  }

  function getAccountStatus(address account) internal view override(InsuredBalancesBase, InsuredJoinBase) returns (uint16) {
    return InsuredBalancesBase.getAccountStatus(account);
  }

  function internalIsAllowedAsHolder(uint16 status) internal view override(InsuredBalancesBase, InsuredJoinBase) returns (bool) {
    return InsuredJoinBase.internalIsAllowedAsHolder(status);
  }

  /// @dev When coverage demand is added, the required coverage is reduced and total demanded coverage increased
  /// @dev Mints to the appropriate insurer
  function internalCoverageDemandAdded(
    address target,
    uint256 amount,
    uint256 premiumRate
  ) internal override {
    _requiredCoverage = uint128(_requiredCoverage - amount);
    _demandedCoverage += uint128(amount);
    // console.log('internalCoverageDemandAdded', amount, _demandedCoverage);
    InsuredBalancesBase.internalMintForCoverage(target, amount, premiumRate);
  }

  /// @dev Calculate how much coverage demand to add
  /// @param target The insurer demand is being added to
  /// @param amount The amount of coverage demand to add
  /// @param unitSize The unit size of the insurer
  /// @return amountToAdd Amount of coverage demand to add
  /// @return premiumRate The rate to pay for the coverage to add
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

  /// @notice Attempt to join an insurer
  function joinPool(IJoinable pool) external onlyAdmin {
    internalJoinPool(pool);
  }

  /// @notice Add coverage demand to the desired insurer
  /// @param target The insurer to add
  /// @param amount The amount of coverage demand to request
  function pushCoverageDemandTo(IInsurerPool target, uint256 amount) external onlyAdmin {
    internalPushCoverageDemandTo(target, amount);
  }

  /// @notice Called when the insurer has process this insured
  /// @param accepted True if this insured was accepted to the pool
  function joinProcessed(bool accepted) external override {
    internalJoinProcessed(msg.sender, accepted);
  }

  ///@notice Reconcile with all chartered insurers
  /// @return receivedCoverage Returns the amount of coverage received
  /// @return receivedCollateral Returns the amount of collateral received (<= receivedCoverage)
  /// @return demandedCoverage Total amount of coverage demanded
  /// @return providedCoverage Total coverage provided (demand satisfied)
  function reconcileWithAllInsurers()
    external
    onlyAdmin
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
      uint256 demandedCoverage,
      uint256 providedCoverage
    )
  {
    return _reconcileWithInsurers(0, type(uint256).max);
  }

  /// @notice Reconcile the coverage and premium with chartered insurers
  /// @param startIndex Index to start at
  /// @param count Max amount of insurers to reconcile with
  /// @return receivedCoverage Returns the amount of coverage received
  /// @return receivedCollateral Returns the amount of collateral received (<= receivedCoverage)
  /// @return demandedCoverage Total amount of coverage demanded
  /// @return providedCoverage Total coverage provided (demand satisfied)
  function reconcileWithInsurers(uint256 startIndex, uint256 count)
    external
    onlyAdmin
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
      uint256 demandedCoverage,
      uint256 providedCoverage
    )
  {
    return _reconcileWithInsurers(startIndex, count);
  }

  /// @dev Go through each insurer and reconcile with them
  /// @dev Does NOT sync the rate
  function _reconcileWithInsurers(uint256 startIndex, uint256 count)
    private
    returns (
      uint256 receivedCoverage,
      uint256 receivedCollateral,
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
      (uint256 cov, uint256 col, DemandedCoverage memory cv) = internalReconcileWithInsurer(IInsurerPoolDemand(insurers[startIndex]), false);
      receivedCoverage += cov;
      receivedCollateral += col;
      demandedCoverage += cv.totalDemand;
      providedCoverage += cv.totalCovered;
    }
  }

  /// @dev Get the values if reconciliation were to occur with the desired Insurers
  /// @dev DOES sync the rate (for the view)
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
      (uint256 c, DemandedCoverage memory cov, ) = internalReconcileWithInsurerView(IInsurerPoolDemand(insurers[startIndex]), totals);
      demandedCoverage += cov.totalDemand;
      providedCoverage += cov.totalCovered;
      receivableCoverage += c;
    }
    (rate, accumulated) = (totals.rate, totals.accum);
  }

  /// @notice Get the values if reconciliation were to occur with all insurers
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

  /// @notice Cancel coverage and get paid out the coverage amount
  /// @param payoutReceiver The receiver of the collateral currency
  /// @param payoutAmount Amount to get paid out for
  function cancelCoverage(address payoutReceiver, uint256 payoutAmount) external onlyAdmin {
    internalCancelRates();

    uint256 payoutRatio = super.totalReceivedCollateral();
    if (payoutRatio <= payoutAmount) {
      payoutRatio = WadRayMath.RAY;
    } else if (payoutRatio > 0) {
      payoutRatio = payoutAmount.rayDiv(payoutRatio);
    } else {
      require(payoutAmount == 0);
    }

    uint256 totalPayout = internalCancelInsurers(getCharteredInsurers(), payoutRatio);
    totalPayout += internalCancelInsurers(getGenericInsurers(), payoutRatio);

    require(totalPayout >= payoutAmount);
    if (payoutAmount > 0) {
      require(payoutReceiver != address(0));
      transferCollateral(payoutReceiver, payoutAmount);
    }
  }

  /// @dev Goes through the insurers and cancels with the payout ratio
  /// @param insurers The insurers to cancel with
  /// @param payoutRatio The ratio of coverage to get paid out
  /// @dev e.g payoutRatio = 7e26 means 30% of coverage is sent back to the insurer
  /// @return totalPayout total amount of coverage paid out to this insured
  function internalCancelInsurers(address[] storage insurers, uint256 payoutRatio) private returns (uint256 totalPayout) {
    IERC20 t = IERC20(collateral());

    for (uint256 i = insurers.length; i > 0; ) {
      address insurer = insurers[--i];
      uint256 allowance = t.allowance(address(this), insurer);
      totalPayout += IInsurerPoolCore(insurer).cancelCoverage(payoutRatio);
      internalDecReceivedCollateral(allowance - t.allowance(address(this), insurer));
      require(t.approve(insurer, 0));
    }
  }

  function internalCollateralReceived(address insurer, uint256 amount) internal override {
    super.internalCollateralReceived(insurer, amount);

    IERC20 t = IERC20(collateral());
    require(t.approve(insurer, t.allowance(address(this), insurer) + amount));
  }

  /// @inheritdoc IInsuredPool
  function offerCoverage(uint256 offeredAmount) external override returns (uint256 acceptedAmount, uint256 rate) {
    return internalOfferCoverage(msg.sender, offeredAmount);
  }

  /// @dev Must be whitelisted to do this
  /// @dev Maximum is _requiredCoverage
  function internalOfferCoverage(address account, uint256 offeredAmount) private returns (uint256 acceptedAmount, uint256 rate) {
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

  function priceOf(address) internal view override returns (uint256) {
    this;
    // TODO price oracle
    return WadRayMath.WAD;
  }

  function internalExpectedPrepay(uint256 atTimestamp) internal view override returns (uint256) {
    return internalExpectedTotals(uint32(atTimestamp)).accum;
  }

  modifier onlyPremiumDistributorOf(address actuary) override {
    _ensureHolder(actuary);
    require(IPremiumActuary(actuary).premiumDistributor() == msg.sender);
    _;
  }

  function internalReservedCollateral() internal view override returns (uint256) {
    return super.totalReceivedCollateral();
  }
}
