// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IJoinable.sol';
import './InsuredBalancesBase.sol';

import 'hardhat/console.sol';

/// @title Insured Join Base
/// @notice Handles tracking and joining insurers
abstract contract InsuredJoinBase is IInsuredPool {
  address[] private _genericInsurers; // ICoverageDistributor[]
  address[] private _charteredInsurers;

  uint16 private constant STATUS_MAX = type(uint16).max;
  uint16 private constant STATUS_NOT_JOINED = STATUS_MAX;
  uint16 private constant STATUS_PENDING = STATUS_MAX - 1;
  uint16 private constant INDEX_MAX = STATUS_MAX - 2;

  function internalJoinPool(IJoinable pool) internal {
    Value.require(address(pool) != address(0));
    uint32 status = getAccountStatus(address(pool));

    State.require(status == 0 || status == STATUS_NOT_JOINED);
    internalSetServiceAccountStatus(address(pool), STATUS_PENDING);

    pool.requestJoin(address(this));
  }

  function getInsurers() public view returns (address[] memory, address[] memory) {
    return (_genericInsurers, _charteredInsurers);
  }

  function getGenericInsurers() internal view returns (address[] storage) {
    return _genericInsurers;
  }

  function getCharteredInsurers() internal view returns (address[] storage) {
    return _charteredInsurers;
  }

  ///@dev Add the Insurer pool if accepted, and set the status of it
  function internalJoinProcessed(address insurer, bool accepted) internal {
    Access.require(getAccountStatus(insurer) == STATUS_PENDING);

    if (accepted) {
      bool chartered = IJoinable(insurer).charteredDemand();
      uint256 index = chartered ? (_charteredInsurers.length << 1) + 1 : (_genericInsurers.length + 1) << 1;
      State.require(index < INDEX_MAX);
      (chartered ? _charteredInsurers : _genericInsurers).push(insurer);
      internalSetServiceAccountStatus(insurer, uint16(index));
    } else {
      internalSetServiceAccountStatus(insurer, STATUS_NOT_JOINED);
    }
  }

  /// @inheritdoc IInsuredPool
  function pullCoverageDemand(
    uint256 amount,
    uint256 maxAmount,
    uint256 loopLimit
  ) external override returns (bool) {
    console.log('pull called');
    uint16 status = getAccountStatus(msg.sender);
    if (status <= INDEX_MAX) {
      Access.require(status > 0);
      return _addCoverageDemandTo(ICoverageDistributor(msg.sender), amount, maxAmount, loopLimit);
    }
    return false;
  }

  function internalPushCoverageDemandTo(ICoverageDistributor target, uint256 maxAmount) internal {
    uint16 status = getAccountStatus(address(target));
    Access.require(status > 0 && status <= INDEX_MAX);
    _addCoverageDemandTo(target, 0, maxAmount, 0);
  }

  /// @dev Add coverage demand to the Insurer and
  /// @param target The insurer to add demand to
  /// @param minAmount The desired min amount of demand to add (soft limit)
  /// @param maxAmount The max amount of demand to add (hard limit)
  /// @return True if there is more demand that can be added
  // slither-disable-next-line calls-loop
  function _addCoverageDemandTo(
    ICoverageDistributor target,
    uint256 minAmount,
    uint256 maxAmount,
    uint256 loopLimit
  ) private returns (bool) {
    uint256 unitSize = target.coverageUnitSize();

    (uint256 amount, uint256 premiumRate) = internalAllocateCoverageDemand(address(target), minAmount, maxAmount, unitSize);
    State.require(amount <= maxAmount);

    amount = amount < unitSize ? 0 : target.addCoverageDemand(amount / unitSize, premiumRate, amount % unitSize != 0, loopLimit);
    if (amount == 0) {
      return false;
    }

    internalCoverageDemandAdded(address(target), amount * unitSize, premiumRate);
    return true;
  }

  /// @dev Calculate how much coverage demand to add
  /// @param target The insurer demand is being added to
  /// @param minAmount The desired min amount of demand to add (soft limit)
  /// @param maxAmount The max amount of demand to add (hard limit)
  /// @param unitSize The unit size of the insurer
  /// @return amount Amount of coverage demand to add
  /// @return premiumRate The rate to pay for the coverage to add
  function internalAllocateCoverageDemand(
    address target,
    uint256 minAmount,
    uint256 maxAmount,
    uint256 unitSize
  ) internal virtual returns (uint256 amount, uint256 premiumRate);

  function internalCoverageDemandAdded(
    address target,
    uint256 amount,
    uint256 premiumRate
  ) internal virtual;

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual;

  function getAccountStatus(address account) internal view virtual returns (uint16);

  function internalIsAllowedAsHolder(uint16 status) internal view virtual returns (bool) {
    return status > 0 && status <= INDEX_MAX;
  }
}
