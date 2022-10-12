// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../libraries/CallData.sol';
import '../funds/Collateralized.sol';
import '../access/AccessHelper.sol';
import './interfaces/ILender.sol';
import './interfaces/IReinvestStrategy.sol';
import '../currency/BorrowBalancesBase.sol';

abstract contract ReinvestManagerBase is AccessHelper, Collateralized, BorrowBalancesBase {
  using EnumerableSet for EnumerableSet.AddressSet;

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

  EnumerableSet.AddressSet private _strategies;

  event StrategyEnabled(address indexed strategy, bool enable);

  /// @dev Enables or disables use of this strategy to invest to it. Disabled strategy can only be used to divest from it.
  function enableStrategy(address strategy, bool enable) external aclHas(AccessFlags.BORROWER_ADMIN) {
    if (enable) {
      Value.require(IReinvestStrategy(strategy).attachManager(address(this)));
      _strategies.add(strategy);
    } else {
      _strategies.remove(strategy);
    }
    emit StrategyEnabled(strategy, enable);
  }

  /// @return true when the strategy is enabled/active.
  function isStrategy(address strategy) public view returns (bool) {
    return _strategies.contains(strategy);
  }

  /// @return list of enabled/active strategies
  function strategies() external view returns (address[] memory) {
    return _strategies.values();
  }

  function _onlyActiveStrategy(address strategy) private view {
    Access.require(isStrategy(strategy));
  }

  modifier onlyActiveStrategy(address strategy) {
    _onlyActiveStrategy(strategy);
    _;
  }

  event LiquidityInvested(address indexed asset, address indexed fromFund, address indexed toStrategy, uint256 amount);
  event LiquidityDivested(address indexed asset, address indexed fromStrategy, address indexed toFund, uint256 amount);
  event LiquidityYieldPulled(address indexed asset, address indexed fromStrategy, address indexed viaFund, uint256 amount);
  event LiquidityLossPaid(address indexed asset, address indexed forStrategy, address indexed viaFund, uint256 amount);

  /// @dev Reinvests `amount` of `asset` from the fund `fromFund` to the strategy `toStrategy`.
  function pushTo(
    address asset,
    address fromFund,
    address toStrategy,
    uint256 amount
  ) external onlyBorrowOpsOf(fromFund) onlyCollateralFund(fromFund) onlyActiveStrategy(toStrategy) {
    internalPushTo(asset, fromFund, toStrategy, amount);
    emit LiquidityInvested(asset, fromFund, toStrategy, amount);
  }

  /// @dev Divests `amount` of `asset` from the strategy `fromStrategy` to the fund `toFund`.
  function pullFrom(
    address asset,
    address fromStrategy,
    address toFund,
    uint256 amount
  ) external returns (uint256) {
    if (!hasAnyAcl(msg.sender, AccessFlags.LIQUIDITY_MANAGER)) {
      _onlyBorrowOpsOf(toFund);
    }

    amount = internalPullFrom(asset, fromStrategy, toFund, amount);
    emit LiquidityDivested(asset, fromStrategy, toFund, amount);
    return amount;
  }

  /// @dev Converts `maxAmount` of asset's yield (an excess above the invested amount) from the strategy 'fromStrategy'
  /// @dev Collected yield is deposited to the fund `viaFund` and the resulting collateral is made available to claim by insurers.
  function pullYieldFrom(
    address asset,
    address fromStrategy,
    address viaFund,
    uint256 maxAmount
  ) external aclHas(AccessFlags.LIQUIDITY_MANAGER) onlyCollateralFund(viaFund) returns (uint256) {
    // NB! The collateral currency will detect mint to itself as a yield payment
    maxAmount = internalPullYieldFrom(asset, fromStrategy, viaFund, maxAmount, collateral());
    emit LiquidityYieldPulled(asset, fromStrategy, viaFund, maxAmount);
    return maxAmount;
  }

  /// @dev Repays liquidity debt incurred by value losses of `forStrategy`. TODO WIP.
  function repayLossFrom(
    address asset,
    address from,
    address forStrategy,
    address viaFund,
    uint256 amount
  ) external aclHas(AccessFlags.LIQUIDITY_MANAGER) onlyCollateralFund(viaFund) {
    // NB! The collateral currency will detect mint to itself as a yield payment
    internalPayLoss(asset, from, forStrategy, viaFund, amount, collateral());
    emit LiquidityLossPaid(asset, forStrategy, viaFund, amount);
  }

  /// @dev Calls a custom method of the `strategy`. Calls to methods of IReinvestStrategy are forbidden.
  function callStrategy(address strategy, bytes calldata callData) external aclHas(AccessFlags.LIQUIDITY_MANAGER) {
    Value.require(Address.isContract(strategy));

    bytes4 selector = CallData.getSelector(callData);
    Access.require(
      !(selector == IReinvestStrategy.approveDivest.selector ||
        selector == IReinvestStrategy.investFrom.selector ||
        selector == IReinvestStrategy.connectAssetBefore.selector ||
        selector == IReinvestStrategy.connectAssetAfter.selector ||
        selector == IReinvestStrategy.investedValueOf.selector)
    );

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = strategy.call{value: 0}(callData);
    Address.verifyCallResult(success, returndata, 'callStrategy failed');
  }

  // TODO func requestLiquidity
}
