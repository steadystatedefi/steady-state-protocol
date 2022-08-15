// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import '../governance/interfaces/IClaimAccessValidator.sol';
import '../interfaces/IPremiumActuary.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';
import './PremiumCollectorBase.sol';
import './InsuredAccessControl.sol';

import 'hardhat/console.sol';

/// @title Insured Pool Base
/// @notice The base pool that tracks how much coverage is requested, provided and paid
/// @dev Reconcilation must be called for the most accurate information
abstract contract InsuredPoolBase is
  IInsuredPool,
  InsuredBalancesBase,
  InsuredJoinBase,
  PremiumCollectorBase,
  IClaimAccessValidator,
  InsuredAccessControl
{
  using WadRayMath for uint256;
  using Math for uint256;

  InsuredParams private _params;
  mapping(address => uint256) private _receivedCollaterals; // [insurer]

  uint8 internal constant DECIMALS = 18;

  constructor(IAccessController acl, address collateral_) ERC20DetailsBase('', '', DECIMALS) InsuredAccessControl(acl, collateral_) {}

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

  event ParamsUpdated(InsuredParams params);

  function internalSetInsuredParams(InsuredParams memory params) internal {
    _params = params;
    emit ParamsUpdated(params);
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

  /// @notice Attempt to join an insurer
  function joinPool(IJoinable pool) external onlyGovernor {
    Value.require(address(pool) != address(0));
    if (!internalHasAppliedApplication()) {
      _applyApprovedApplication();
    }

    State.require(IERC20(premiumToken()).balanceOf(address(this)) >= expectedPrepay(uint32(block.timestamp)));

    internalJoinPool(pool);
  }

  /// @notice Add coverage demand to the desired insurer
  /// @param target The insurer to add
  /// @param amount The amount of coverage demand to request
  function pushCoverageDemandTo(ICoverageDistributor target, uint256 amount) external onlyGovernorOr(AccessFlags.INSURED_OPS) {
    internalPushCoverageDemandTo(target, amount);
  }

  function setInsuredParams(InsuredParams calldata params) external onlyGovernorOr(AccessFlags.INSURED_OPS) {
    internalSetInsuredParams(params);
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

  event CoverageReconciled(address indexed insurer, uint256 receivedCoverage, uint256 receivedCollateral);

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
      count += startIndex;
    }
    if (count > startIndex && count < max) {
      max = count;
    }

    for (; startIndex < max; startIndex++) {
      address insurer = insurers[startIndex];
      (uint256 cov, uint256 col, DemandedCoverage memory cv) = internalReconcileWithInsurer(ICoverageDistributor(insurer), false);
      emit CoverageReconciled(insurer, cov, col);

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

  event CoverageCancelled(uint256 expectedPayout, uint256 actualPayout, address indexed payoutReceiver);

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

    emit CoverageCancelled(expectedPayout, totalPayout, payoutReceiver);
  }

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

      uint256 receivedCollateral = _receivedCollaterals[insurer];
      _receivedCollaterals[insurer] = 0;

      require(t.approve(insurer, receivedCollateral));

      totalPayout += ICancellableCoverage(insurer).cancelCoverage(address(this), payoutRatio);

      internalDecReceivedCollateral(receivedCollateral - t.allowance(address(this), insurer));
      require(t.approve(insurer, 0));
    }
  }

  function internalPriceOf(address asset) internal view virtual override returns (uint256) {
    return getPricer().getAssetPrice(asset);
  }

  function internalPullPriceOf(address asset) internal virtual override returns (uint256) {
    return getPricer().pullAssetPrice(asset, 0);
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

  event PrepayWithdrawn(uint256 amount, address indexed recipient);

  function withdrawPrepay(address recipient, uint256 amount) external override onlyGovernor {
    amount = internalWithdrawPrepay(recipient, amount);
    emit PrepayWithdrawn(amount, recipient);
  }

  function governor() public view returns (address) {
    return governorAccount();
  }

  function setGovernor(address addr) external onlyGovernorOr(AccessFlags.INSURED_ADMIN) {
    internalSetGovernor(addr);
  }

  function canClaimInsurance(address claimedBy) public view virtual override returns (bool) {
    return claimedBy == governorAccount();
  }

  event CoverageDemandOffered(address indexed offeredBy, uint256 offeredAmount, uint256 acceptedAmount, uint256 rate);

  /// @inheritdoc IInsuredPool
  function offerCoverage(uint256 offeredAmount) external override returns (uint256 acceptedAmount, uint256 rate) {
    (acceptedAmount, rate) = internalOfferCoverage(msg.sender, offeredAmount);
    emit CoverageDemandOffered(msg.sender, offeredAmount, acceptedAmount, rate);
  }

  function internalOfferCoverage(address account, uint256 offeredAmount) internal virtual returns (uint256 acceptedAmount, uint256 rate);
}
