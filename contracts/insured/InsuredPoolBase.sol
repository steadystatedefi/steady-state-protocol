// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';
import './PremiumCollectorBase.sol';
import '../interfaces/IPremiumActuary.sol';
import './InsuredAccessControl.sol';

import 'hardhat/console.sol';

/// @title Insured Pool Base
/// @notice The base pool that tracks how much coverage is requested, provided and paid
/// @dev Reconcilation must be called for the most accurate information
abstract contract InsuredPoolBase is IInsuredPool, InsuredBalancesBase, InsuredJoinBase, PremiumCollectorBase, InsuredAccessControl {
  using WadRayMath for uint256;
  using Math for uint256;

  // TODO support for rate bands

  uint96 private _requiredCoverage;
  uint96 private _demandedCoverage;
  uint64 private _premiumRate;

  InsuredParams private _params;

  uint8 internal constant DECIMALS = 18;

  constructor(IAccessController acl, address collateral_) ERC20DetailsBase('', '', DECIMALS) GovernedHelper(acl, collateral_) {}

  function _initializeCoverageDemand(uint256 requiredCoverage, uint256 premiumRate) internal {
    State.require(_premiumRate == 0);
    Value.require(premiumRate != 0);
    Value.require((_requiredCoverage = uint96(requiredCoverage)) == requiredCoverage);
    Value.require((_premiumRate = uint64(premiumRate)) == premiumRate);
  }

  function applyApprovedApplication() external onlyGovernor {
    State.require(!internalHasAppliedApplication());
    _applyApprovedApplication();
  }

  function internalHasAppliedApplication() internal view returns (bool) {
    return premiumToken() != address(0);
  }

  function internalGetApprovedPolicy() internal returns (IApprovalCatalog.ApprovedPolicy memory) {
    return approvalCatalog().applyApprovedApplication();
  }

  function _applyApprovedApplication() private {
    IApprovalCatalog.ApprovedPolicy memory ap = internalGetApprovedPolicy();

    State.require(ap.insured == address(this));
    State.require(ap.expiresAt > block.timestamp);

    _initializeERC20(ap.policyName, ap.policySymbol, DECIMALS);
    _initializePremiumCollector(ap.premiumToken, ap.minPrepayValue, ap.rollingAdvanceWindow);
  }

  function collateral() public view override(ICollateralized, Collateralized, PremiumCollectorBase) returns (address) {
    return Collateralized.collateral();
  }

  function internalAddRequiredCoverage(uint256 amount) internal {
    _requiredCoverage += amount.asUint96();
  }

  function internalSetInsuredParams(InsuredParams memory params) internal {
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
    _requiredCoverage = uint96(_requiredCoverage - amount);
    _demandedCoverage += uint96(amount);
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

  /// @notice Attempt to join an insurer
  function joinPool(IJoinable pool) external onlyGovernor {
    Value.require(address(pool) != address(0));
    if (!internalHasAppliedApplication()) {
      _applyApprovedApplication();
    }

    State.require(IERC20(premiumToken()).balanceOf(address(this)) >= expectedPrepay(uint32(block.timestamp)));

    internalJoinPool(pool);
  }

  function setCoverageDemand(uint256 requiredCoverage, uint256 premiumRate) external onlyGovernor {
    if (internalHasAppliedApplication()) {
      IApprovalCatalog.ApprovedPolicy memory ap = internalGetApprovedPolicy();
      Value.require(premiumRate >= ap.basePremiumRate);
    }
    _initializeCoverageDemand(requiredCoverage, premiumRate);
  }

  /// @notice Add coverage demand to the desired insurer
  /// @param target The insurer to add
  /// @param amount The amount of coverage demand to request
  function pushCoverageDemandTo(ICoverageDistributor target, uint256 amount) external onlyGovernorOr(AccessFlags.INSURED_OPS) {
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
    onlyGovernorOr(AccessFlags.INSURED_OPS)
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
    onlyGovernorOr(AccessFlags.INSURED_OPS)
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
      (uint256 cov, uint256 col, DemandedCoverage memory cv) = internalReconcileWithInsurer(ICoverageDistributor(insurers[startIndex]), false);
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
      (uint256 c, DemandedCoverage memory cov, ) = internalReconcileWithInsurerView(ICoverageDistributor(insurers[startIndex]), totals);
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

  // TODO cancelCoverageDemnad

  /// @notice Cancel coverage and get paid out the coverage amount
  /// @param payoutReceiver The receiver of the collateral currency
  /// @param expectedPayout Amount to get paid out for
  function cancelCoverage(address payoutReceiver, uint256 expectedPayout) external onlyGovernorOr(AccessFlags.INSURED_OPS) {
    internalCancelRates();

    uint256 payoutRatio = super.totalReceivedCollateral();
    if (payoutRatio <= expectedPayout) {
      payoutRatio = WadRayMath.RAY;
    } else if (payoutRatio > 0) {
      payoutRatio = expectedPayout.rayDiv(payoutRatio);
    } else {
      require(expectedPayout == 0);
    }

    uint256 totalPayout = internalCancelInsurers(getCharteredInsurers(), payoutRatio);
    totalPayout += internalCancelInsurers(getGenericInsurers(), payoutRatio);

    // NB! it is possible for totalPayout < expectedPayout when drawdown takes place
    if (totalPayout > 0) {
      require(payoutReceiver != address(0));
      transferCollateral(payoutReceiver, totalPayout);
    }
  }

  mapping(address => uint256) private _receivedCollaterals; // [insurer]

  function internalCollateralReceived(address insurer, uint256 amount) internal override {
    super.internalCollateralReceived(insurer, amount);
    _receivedCollaterals[insurer] += amount;
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

      uint256 allowance = _receivedCollaterals[insurer];
      _receivedCollaterals[insurer] = 0;

      require(t.approve(insurer, allowance));

      totalPayout += ICancellableCoverage(insurer).cancelCoverage(address(this), payoutRatio);

      internalDecReceivedCollateral(allowance - t.allowance(address(this), insurer));
      require(t.approve(insurer, 0));
    }
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
      _requiredCoverage = uint96(acceptedAmount - offeredAmount);
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
    // TODO use maxRate (demanded coverage)
    return internalExpectedTotals(uint32(atTimestamp)).accum;
  }

  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external override {
    _ensureHolder(actuary);
    Access.require(IPremiumActuary(actuary).premiumDistributor() == msg.sender);
    internalCollectPremium(token, amount, value);
  }

  function internalReservedCollateral() internal view override returns (uint256) {
    return super.totalReceivedCollateral();
  }

  function withdrawPrepay(address recipient, uint256 amount) external override onlyGovernor {
    internalWithdrawPrepay(recipient, amount);
  }

  function governor() public view returns (address) {
    return governorAccount();
  }

  function setGovernor(address addr) external onlyGovernorOr(AccessFlags.INSURED_ADMIN) {
    internalSetGovernor(addr);
  }
}
