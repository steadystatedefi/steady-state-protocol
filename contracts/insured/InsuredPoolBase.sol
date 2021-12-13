// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';

import 'hardhat/console.sol';

// Insured pool tracks how much coverage was requested to Insurer pool and how much is provided
// reconcilation will ensure the correct amount of premium is paid
abstract contract InsuredPoolBase is IInsuredPool, InsuredBalancesBase, InsuredJoinBase {
  uint128 private _requiredCoverage;
  uint128 private _demandedCoverage;

  uint64 private _premiumRate;

  InsuredParams private _params;

  constructor(uint256 requiredCoverage, uint64 premiumRate) {
    require((_requiredCoverage = uint128(requiredCoverage)) == requiredCoverage);
    _premiumRate = premiumRate;
  }

  //TODO: THIS IS A TEMPORARY FUNCTION
  function increaseRequiredCoverage(uint256 amount) external {
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
    // console.log('internalCoverageDemandAdded', target, amount, _totalDemand);
    _requiredCoverage = uint128(_requiredCoverage - amount);
    _demandedCoverage += uint128(amount);
    InsuredBalancesBase.internalMintForCoverage(target, amount, premiumRate, address(0));
  }

  ///@dev Adjusts the required and demanded coverage from an investment
  ///TODO: premiumrate(?)
  function internalHandleDirectInvestment(
    uint256 amount,
    uint256 minAmount,
    uint256
  ) internal override returns (uint256 availableAmount, uint64 premiumRate) {
    availableAmount = _requiredCoverage;
    if (availableAmount > amount) {
      _requiredCoverage = uint128(availableAmount - amount);
      availableAmount = amount;
    } else if (availableAmount > 0 && availableAmount >= minAmount) {
      _requiredCoverage = 0;
    } else {
      return (0, _premiumRate);
    }

    require((_demandedCoverage = uint128(amount = _demandedCoverage + availableAmount)) == amount);

    return (availableAmount, _premiumRate);
  }

  function internalAllocateCoverageDemand(
    address target,
    uint256 amount,
    uint256 unitSize
  ) internal view override returns (uint256 amountToAdd, uint256 premiumRate) {
    // console.log('internalAllocateCoverageDemand', target, amount, unitSize);
    // console.log('internalAllocateCoverageDemand', _totalDemand, _premiumRate);
    target;
    amount;
    unitSize;
    return (_requiredCoverage, _premiumRate);
  }

  modifier onlyAdmin() virtual {
    _;
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

  // function totalCoverage() public view returns(uint256 required, uint256 demanded, uint256 received) {
  //   return (_requiredCoverage, _demandedCoverage, IERC20(collateral()).balanceOf(address(this)));
  // }
}
