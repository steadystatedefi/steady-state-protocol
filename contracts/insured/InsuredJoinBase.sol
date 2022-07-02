// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IJoinable.sol';
import './InsuredBalancesBase.sol';

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
    require(address(pool) != address(0));
    uint32 status = getAccountStatus(address(pool));

    require(status == 0 || status == STATUS_NOT_JOINED);
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

  function getDemandOnJoin() internal view virtual returns (uint256) {
    return ~uint256(0);
  }

  ///@dev Add the Insurer pool if accepted, and set the status of it
  function internalJoinProcessed(address insurer, bool accepted) internal {
    require(getAccountStatus(insurer) == STATUS_PENDING);

    if (accepted) {
      bool chartered = IJoinable(insurer).charteredDemand();
      uint256 index = chartered ? (_charteredInsurers.length << 1) + 1 : (_genericInsurers.length + 1) << 1;
      require(index < INDEX_MAX);
      (chartered ? _charteredInsurers : _genericInsurers).push(insurer);
      internalSetServiceAccountStatus(insurer, uint16(index));
      _addCoverageDemandTo(ICoverageDistributor(insurer), getDemandOnJoin());
    } else {
      internalSetServiceAccountStatus(insurer, STATUS_NOT_JOINED);
    }
  }

  /// @inheritdoc IInsuredPool
  function pullCoverageDemand() external override returns (bool) {
    uint16 status = getAccountStatus(msg.sender);
    if (status > INDEX_MAX) {
      return false;
    }

    require(status > 0);
    return _addCoverageDemandTo(ICoverageDistributor(msg.sender), 0);
  }

  function internalPushCoverageDemandTo(ICoverageDistributor target, uint256 amount) internal {
    uint16 status = getAccountStatus(address(target));
    require(status > 0 && status <= INDEX_MAX);
    _addCoverageDemandTo(target, amount);
  }

  /// @dev Add coverage demand to the Insurer and
  /// @param target The insurer to add demand to
  /// @param amount The desired amount of demand to add
  /// @return True if there is more demand that can be added
  function _addCoverageDemandTo(ICoverageDistributor target, uint256 amount) private returns (bool) {
    uint256 unitSize = target.coverageUnitSize();

    (uint256 amountAdd, uint256 premiumRate) = internalAllocateCoverageDemand(address(target), amount, unitSize);
    require(amountAdd <= amount);

    amountAdd = amountAdd < unitSize ? 0 : target.addCoverageDemand(amountAdd / unitSize, premiumRate, amountAdd % unitSize != 0, 0);
    if (amountAdd == 0) {
      return false;
    }

    amountAdd *= unitSize;
    internalCoverageDemandAdded(address(target), amountAdd, premiumRate);

    return amountAdd < amount;
  }

  function internalAllocateCoverageDemand(
    address target,
    uint256 amount,
    uint256 unitSize
  ) internal virtual returns (uint256 amountToAdd, uint256 premiumRate);

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
