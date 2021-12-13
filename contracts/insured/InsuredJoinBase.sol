// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IJoinable.sol';
import './InsuredBalancesBase.sol';

//InsuredJoinBase handles Insured pool requesting to join an Insurer
abstract contract InsuredJoinBase is IInsuredPool {
  address[] private _genericInsurers; // IInsurerPool[]
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

  function getCharteredInsurers() internal view returns (address[] storage) {
    return _charteredInsurers;
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
      _pushCoverageDemand(IInsurerPool(insurer), 0);
    } else {
      internalSetServiceAccountStatus(insurer, STATUS_NOT_JOINED);
    }
  }

  function pullCoverageDemand() external override returns (bool) {
    uint16 status = getAccountStatus(msg.sender);
    if (status > INDEX_MAX) {
      return false;
    }

    require(status > 0);
    return _pushCoverageDemand(IInsurerPool(msg.sender), 0);
  }

  function internalPushCoverageDemandTo(IInsurerPool target, uint256 amount) internal {
    uint16 status = getAccountStatus(address(target));
    require(status > 0 && status <= INDEX_MAX);
    _pushCoverageDemand(target, amount);
  }

  function _pushCoverageDemand(IInsurerPool target, uint256 amount) private returns (bool) {
    return _addCoverageDemandTo(target, amount);
  }

  ///@dev Add coverage demand to the Insurer and return if there is more demand that can be added(?)
  function _addCoverageDemandTo(IInsurerPool target, uint256 amount) private returns (bool) {
    uint256 unitSize = IInsurerPool(target).coverageUnitSize();
    uint256 premiumRate;
    (amount, premiumRate) = internalAllocateCoverageDemand(address(target), amount, unitSize);
    if (amount < unitSize) {
      return false;
    }

    uint256 amountAdded = target.addCoverageDemand(amount / unitSize, premiumRate, amount % unitSize != 0);
    if (amountAdded == 0) {
      return false;
    }

    amountAdded *= unitSize;
    require(amountAdded <= amount);
    internalCoverageDemandAdded(address(target), amountAdded, premiumRate);

    return amountAdded < amount;
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
