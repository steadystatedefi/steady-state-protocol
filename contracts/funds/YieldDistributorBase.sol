// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../access/AccessHelper.sol';

import '../access/AccessHelper.sol';
import './interfaces/IManagedYieldDistributor.sol';
import './YieldStakerBase.sol';
import './YieldStreamerBase.sol';

contract YieldDistributorBase is IManagedYieldDistributor, YieldStakerBase, YieldStreamerBase {
  using SafeERC20 for IERC20;
  using Math for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  uint128 private _totalIntegral;
  uint32 private _lastUpdatedAt;

  constructor(IAccessController acl, address collateral_) AccessHelper(acl) Collateralized(collateral_) {}

  function registerStakeAsset(address asset, bool register) external override onlyCollateralCurrency {
    if (register) {
      internalAddAsset(asset);
    } else {
      internalRemoveAsset(asset);
    }
  }

  function internalAddYieldExcess(uint256 value) internal override(YieldStakerBase, YieldStreamerBase) {
    YieldStakerBase.internalAddYieldExcess(value);
  }

  function internalGetTimeIntegral() internal view override returns (uint256 totalIntegral, uint32 lastUpdatedAt) {
    return (_totalIntegral, _lastUpdatedAt);
  }

  function internalSetTimeIntegral(uint256 totalIntegral, uint32 lastUpdatedAt) internal override {
    (_totalIntegral, _lastUpdatedAt) = (totalIntegral.asUint128(), lastUpdatedAt);
  }

  function internalGetRateIntegral(uint32 from, uint32 till) internal override(YieldStakerBase, YieldStreamerBase) returns (uint256) {
    return YieldStreamerBase.internalGetRateIntegral(from, till);
  }

  function internalCalcRateIntegral(uint32 from, uint32 till) internal view override(YieldStakerBase, YieldStreamerBase) returns (uint256) {
    return YieldStreamerBase.internalCalcRateIntegral(from, till);
  }

  function internalPullYield(uint256 availableYield, uint256 requestedYield) internal override(YieldStakerBase, YieldStreamerBase) returns (bool) {
    return YieldStreamerBase.internalPullYield(availableYield, requestedYield);
  }

  function _onlyTrustedBorrower(address addr) private view {
    Access.require(hasAnyAcl(addr, AccessFlags.LIQUIDITY_BORROWER) && internalIsYieldSource(addr));
  }

  modifier onlyTrustedBorrower(address addr) {
    _onlyTrustedBorrower(addr);
    _;
  }

  function verifyBorrowUnderlying(address account, uint256 value)
    external
    override
    onlyLiquidityProvider
    onlyTrustedBorrower(account)
    returns (bool)
  {
    internalApplyBorrow(value);
    return true;
  }

  function verifyRepayUnderlying(address account, uint256 value) external override onlyLiquidityProvider onlyTrustedBorrower(account) returns (bool) {
    internalApplyRepay(value);
    return true;
  }

  function addYieldPayout(uint256 amount, uint256 expectedRate) external {
    if (amount > 0) {
      transferCollateralFrom(msg.sender, address(this), amount);
    }
    internalSyncTotal();
    internalAddYieldPayout(msg.sender, amount, expectedRate);
  }

  function addYieldSource(address source, uint8 sourceType) external aclHas(AccessFlags.BORROWER_ADMIN) {
    internalAddYieldSource(source, sourceType);
  }

  function removeYieldSource(address source) external aclHas(AccessFlags.BORROWER_ADMIN) {
    internalSyncTotal();
    internalRemoveYieldSource(source);
  }

  // TODO pause, pause_asset, pause_source_borrow

  function getYieldSource(address source)
    external
    view
    returns (
      uint8 sourceType,
      uint96 expectedRate,
      uint32 since
    )
  {
    return internalGetYieldSource(source);
  }

  function getYieldInfo()
    external
    view
    returns (
      uint256 rate,
      uint256 debt,
      uint32 cutOff
    )
  {
    return internalGetYieldInfo();
  }

  function internalPullYieldFrom(uint8, address) internal virtual override returns (uint256) {
    Errors.notImplemented();
    return 0;
  }
}
