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

/// @dev A template of a generic insured policy. Is also referred to as 'pool' - because multiple insurers can cover a single policy.
/// @dev This template provides all necessary functionality: Access control, tracking insurers, management of demand distribution collection,
/// @dev collecting coverage, and streaming of premium. The missing part is keeping a registry of demand by rate bands.
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

  uint256 private _totalReceivedCoverage;
  mapping(address => uint256) private _receivedCoverage; // [insurer]

  uint8 internal constant DECIMALS = 18;

  constructor(IAccessController acl, address collateral_) ERC20DetailsBase('', '', DECIMALS) InsuredAccessControl(acl, collateral_) {}

  /// @dev Reads and applies an approved application from the ApprovalCatalog. Can only be applied once.
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

  /// @inheritdoc ICollateralized
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

  /// @dev Initiates joining to an insurer.
  /// @dev Must have an approved application in the ApprovalCatalog, and must have a sufficient prepayment of premium token.
  function joinPool(IJoinable pool) external onlyGovernor {
    Value.require(address(pool) != address(0));
    if (!internalHasAppliedApplication()) {
      _applyApprovedApplication();
    }

    State.require(IERC20(premiumToken()).balanceOf(address(this)) >= expectedPrepay(uint32(block.timestamp)));

    internalJoinPool(pool);
  }

  /// @dev Attemps to add coverage demands to the desired insurers. An insurer might take only a fraction of the pushed demand.
  /// @param targets is a list of insurers to add demand to
  /// @param amounts is a list of amount of coverage demand to push to insurers
  function pushCoverageDemandTo(ICoverageDistributor[] calldata targets, uint256[] calldata amounts)
    external
    onlyGovernorOr(AccessFlags.INSURED_OPS)
  {
    Value.require(targets.length == amounts.length);
    for (uint256 i = 0; i < targets.length; i++) {
      internalPushCoverageDemandTo(targets[i], amounts[i]);
    }
  }

  /// @dev Sets params of this policy. See IInsuredPool.InsuredParams
  function setInsuredParams(InsuredParams calldata params) external onlyGovernorOr(AccessFlags.INSURED_OPS) {
    internalSetInsuredParams(params);
  }

  /// @inheritdoc IInsuredPool
  function joinProcessed(bool accepted) external override {
    internalJoinProcessed(msg.sender, accepted);
  }

  /// @dev Reconciles coverage and premium with chartered insurers. Updates premium requirements, adds collateral into escrow.
  /// @param startIndex in the chartered list to start with
  /// @param count is max number of insurers to reconcile with, 0 == max
  /// @return receivedCoverage is the amount of coverage added (allocated by insurers since the previous reconciliation).
  /// @return receivedCollateral is the amount of collateral currency added into escrow (<= receivedCoverage).
  /// @return demandedCoverage is total amount of demanded coverage
  /// @return providedCoverage is total coverage provided (i.e. demand satisfied)
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
    return _reconcileWithInsurers(startIndex, count > 0 ? count : type(uint256).max);
  }

  event CoverageReconciled(address indexed insurer, uint256 receivedCoverage, uint256 receivedCollateral);

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

  /// @dev Calculates expected changes to coverage and premium changes for the chartered `insurer` as if you call reconciliation now.
  /// @return r is IInsuredPool.ReceivableByReconcile with the expected changes and stats.
  function receivableByReconcileWithInsurer(address insurer) external view returns (ReceivableByReconcile memory r) {
    Balances.RateAcc memory totals = internalSyncTotals();
    (uint256 c, DemandedCoverage memory cov, ) = internalReconcileWithInsurerView(ICoverageDistributor(insurer), totals);
    r.demandedCoverage = cov.totalDemand;
    r.providedCoverage = cov.totalCovered;
    r.receivableCoverage = c;
    (r.rate, r.accumulated) = (totals.rate, totals.accum);
  }

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

  /// @dev  Get the values if reconciliation were to occur with all insurers
  function receivableByReconcileWithInsurers(uint256 startIndex, uint256 count)
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
    return _reconcileWithInsurersView(startIndex, count > 0 ? count : type(uint256).max);
  }

  event CoverageFullyCancelled(uint256 expectedPayout, uint256 actualPayout, address indexed payoutReceiver);

  /// @dev Cancels coverage and pays out an insurance claim. When payout is non-zero, it must be approved in the ApprovalCatalog.
  /// @dev This method iterates through all insurers and takes the payout proportionally from each insurer.
  /// @param payoutReceiver will receive the payout (collateral currency). The payout may be deducted by known debts (e.g. lack of premium).
  /// @param expectedPayout to be paid
  function cancelCoverage(address payoutReceiver, uint256 expectedPayout) external onlyGovernorOr(AccessFlags.INSURED_OPS) {
    internalCancelRates();

    uint256 payoutRatio = _totalReceivedCoverage;
    if (payoutRatio <= expectedPayout) {
      payoutRatio = WadRayMath.RAY;
    } else if (payoutRatio > 0) {
      payoutRatio = expectedPayout.rayDiv(payoutRatio);
    } else {
      Value.require(expectedPayout == 0);
    }

    uint256 totalPayout = internalCancelInsurers(getCharteredInsurers(), payoutRatio);
    totalPayout += internalCancelInsurers(getGenericInsurers(), payoutRatio);

    // NB! it is possible for totalPayout < expectedPayout when drawdown or premium debt are present
    if (totalPayout > 0) {
      Value.require(payoutReceiver != address(0));
      transferCollateral(payoutReceiver, totalPayout);
    }

    emit CoverageFullyCancelled(expectedPayout, totalPayout, payoutReceiver);
  }

  event CoverageCancelled(address indexed insurer, uint256 payoutRatio, uint256 actualPayout);

  /// @dev Goes through the insurers and cancels with the payout ratio
  /// @param insurers to cancel with
  /// @param payoutRatio is a RAY-based share of coverage to be given to this insured, e.g. 7e26 means 70% to this insured and 30% to the insurer.
  /// @return totalPayout total amount of coverage paid out to this insured
  function internalCancelInsurers(address[] storage insurers, uint256 payoutRatio) private returns (uint256 totalPayout) {
    for (uint256 i = insurers.length; i > 0; ) {
      address insurer = insurers[--i];

      uint256 payout = ICancellableCoverage(insurer).cancelCoverage(address(this), payoutRatio);
      totalPayout += payout;
      emit CoverageCancelled(insurer, payoutRatio, payout);

      _totalReceivedCoverage -= _receivedCoverage[insurer];
      delete _receivedCoverage[insurer];
    }
  }

  function internalCoverageReceived(
    address insurer,
    uint256 receivedCoverage,
    uint256
  ) internal override {
    _receivedCoverage[insurer] += receivedCoverage;
    _totalReceivedCoverage += receivedCoverage;
  }

  /// @return receivedCoverage is the amount of coverage allocated by all insurers. Updated by reconcilation.
  /// @return receivedCollateral is the amount of collateral currency in the escrow (<= receivedCoverage). Updated by reconcilation.
  function totalReceived() public view returns (uint256 receivedCoverage, uint256 receivedCollateral) {
    return (_totalReceivedCoverage, totalReceivedCollateral());
  }

  function internalPriceOf(address asset) internal view virtual override returns (uint256) {
    return getPricer().getAssetPrice(asset);
  }

  function internalPullPriceOf(address asset) internal virtual override returns (uint256) {
    return getPricer().pullAssetPrice(asset, 0);
  }

  function internalExpectedPrepay(uint256 atTimestamp) internal view override returns (uint256) {
    return internalExpectedTotals(uint32(atTimestamp)).accum;
  }

  /// @inheritdoc IPremiumSource
  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external override {
    _ensureHolder(actuary);
    Access.require(IPremiumActuary(actuary).premiumDistributor() == msg.sender);
    internalCollectPremium(token, amount, value, msg.sender);
  }

  event PrepayWithdrawn(uint256 amount, address indexed recipient);

  /// @inheritdoc IPremiumCollector
  function withdrawPrepay(address recipient, uint256 amount) external override onlyGovernor {
    amount = internalWithdrawPrepay(recipient, amount);
    emit PrepayWithdrawn(amount, recipient);
  }

  /// @return address of a governor
  function governor() public view returns (address) {
    return governorAccount();
  }

  /// @dev Sets a governor. When the governor is a contract it can get callbacks by declaring IInsuredGovernor support via ERC165.
  function setGovernor(address addr) external onlyGovernorOr(AccessFlags.INSURED_ADMIN) {
    internalSetGovernor(addr);
  }

  /// @inheritdoc IClaimAccessValidator
  function canClaimInsurance(address claimedBy) public view virtual override returns (bool) {
    return internalHasAppliedApplication() && claimedBy == governorAccount();
  }

  event CoverageDemandOffered(address indexed offeredBy, uint256 offeredAmount, uint256 acceptedAmount, uint256 rate);

  /// @inheritdoc IInsuredPool
  function offerCoverage(uint256 offeredAmount) external override returns (uint256 acceptedAmount, uint256 rate) {
    (acceptedAmount, rate) = internalOfferCoverage(msg.sender, offeredAmount);
    emit CoverageDemandOffered(msg.sender, offeredAmount, acceptedAmount, rate);
  }

  function internalOfferCoverage(address account, uint256 offeredAmount) internal virtual returns (uint256 acceptedAmount, uint256 rate);
}
