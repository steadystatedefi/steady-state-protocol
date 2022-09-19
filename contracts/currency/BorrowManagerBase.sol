// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/tokens/ERC20Base.sol';
import '../tools/Errors.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../funds/Collateralized.sol';
import './interfaces/ILender.sol';
import './interfaces/IReinvestStrategy.sol';
import './BorrowBalancesBase.sol';

abstract contract BorrowManagerBase is Collateralized, BorrowBalancesBase {
  using Math for uint256;
  using WadRayMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

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
    Access.require(ILender(fund).isBorrowOps(msg.sender));
  }

  modifier onlyBorrowOpsOf(address fund) {
    _onlyBorrowOpsOf(fund);
    _;
  }

  modifier onlyBorrowOps() {
    _;
  }

  function pushTo(
    address token,
    address fromFund,
    address toStrategy,
    uint256 amount
  ) external onlyBorrowOpsOf(fromFund) onlyCollateralFund(fromFund) {
    return internalPushTo(token, fromFund, toStrategy, amount);
  }

  function pullFrom(
    address token,
    address fromStrategy,
    address toFund,
    uint256 amount
  ) external onlyBorrowOpsOf(toFund) returns (uint256) {
    return internalPullFrom(token, fromStrategy, toFund, amount);
  }

  function pullYieldFrom(
    address token,
    address fromStrategy,
    address viaFund,
    uint256 maxAmount
  ) external onlyBorrowOps onlyCollateralFund(viaFund) returns (uint256) {
    // NB! The collateral currency will detect mint to itself as a yield payment
    return internalPullYieldFrom(token, fromStrategy, viaFund, maxAmount, collateral());
  }

  // TODO func repayLoss
  // TODO func requestLiquidity
}
