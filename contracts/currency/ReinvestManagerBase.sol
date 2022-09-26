// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../funds/Collateralized.sol';
import '../access/AccessHelper.sol';
import './interfaces/ILender.sol';
import './interfaces/IReinvestStrategy.sol';
import '../currency/BorrowBalancesBase.sol';

abstract contract ReinvestManagerBase is AccessHelper, Collateralized, BorrowBalancesBase {
  constructor(IAccessController acl, address collateral_) AccessHelper(acl) Collateralized(collateral_) {}

  function _onlyCollateralFund(address fund) private view {
    address cc = collateral();
    Value.require(ILender(fund).collateral() == cc);
    Value.require(IManagedCollateralCurrency(cc).isLiquidityProvider(fund));
  }

  modifier onlyCollateralFund(address fund) {
    _onlyCollateralFund(fund);
    _;
  }

  function _onlyBorrowOpsOf(address fund) private view {
    Access.require(fund != address(0) && ILender(fund).isBorrowOps(msg.sender));
  }

  modifier onlyBorrowOpsOf(address fund) {
    _onlyBorrowOpsOf(fund);
    _;
  }

  mapping(address => uint256) private _strategies;

  function enableStrategy(address strategy, bool enable) external aclHas(AccessFlags.BORROWER_ADMIN) {
    Value.require(strategy != address(0));
    _strategies[strategy] = enable ? 1 : 0;
  }

  function isStrategy(address strategy) public view returns (bool) {
    return _strategies[strategy] != 0;
  }

  function _onlyActiveStrategy(address strategy) private view {
    Access.require(isStrategy(strategy));
  }

  modifier onlyActiveStrategy(address strategy) {
    _;
  }

  function pushTo(
    address token,
    address fromFund,
    address toStrategy,
    uint256 amount
  ) external onlyBorrowOpsOf(fromFund) onlyCollateralFund(fromFund) onlyActiveStrategy(toStrategy) {
    return internalPushTo(token, fromFund, toStrategy, amount);
  }

  function pullFrom(
    address token,
    address fromStrategy,
    address toFund,
    uint256 amount
  ) external aclHas(AccessFlags.LIQUIDITY_MANAGER) returns (uint256) {
    return internalPullFrom(token, fromStrategy, toFund, amount);
  }

  function pullYieldFrom(
    address token,
    address fromStrategy,
    address viaFund,
    uint256 maxAmount
  ) external aclHas(AccessFlags.LIQUIDITY_MANAGER) onlyCollateralFund(viaFund) returns (uint256) {
    // NB! The collateral currency will detect mint to itself as a yield payment
    return internalPullYieldFrom(token, fromStrategy, viaFund, maxAmount, collateral());
  }

  function repayLossFrom(
    address token,
    address from,
    address forStrategy,
    address viaFund,
    uint256 amount
  ) external aclHas(AccessFlags.LIQUIDITY_MANAGER) onlyCollateralFund(viaFund) {
    // NB! The collateral currency will detect mint to itself as a yield payment
    internalPayLoss(token, from, forStrategy, viaFund, amount, collateral());
  }

  // TODO func requestLiquidity
}
