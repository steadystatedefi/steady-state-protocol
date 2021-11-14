// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IJoinable.sol';
import './InsuredBalancesBase.sol';

abstract contract InsuredJoinBase is IInsuredPool {
  address[] private _insurers; // IInsurerPool[]

  uint16 private constant STATUS_MAX = type(uint16).max;
  uint16 private constant STATUS_NOT_JOINED = STATUS_MAX;
  uint16 private constant STATUS_PENDING = STATUS_MAX - 1;

  uint16 private constant INDEX_MAX = STATUS_MAX - 16;

  function internalJoinPool(IJoinable pool) internal {
    require(address(pool) != address(0));
    uint32 status = getAccountStatus(address(pool));

    require(status == 0 || status == STATUS_NOT_JOINED);
    internalSetServiceAccountStatus(address(pool), STATUS_PENDING);

    pool.requestJoin(address(this));
  }

  function getInsurers() public view returns (address[] memory) {
    return _insurers;
  }

  function joinProcessed(bool accepted) external override {
    require(getAccountStatus(msg.sender) == STATUS_PENDING);

    if (accepted) {
      require(_insurers.length < INDEX_MAX);
      _insurers.push(msg.sender);
      uint16 index = uint16(_insurers.length);
      internalSetServiceAccountStatus(msg.sender, index);
      _pushCoverageDemand(IInsurerPool(msg.sender), 0);
    } else {
      internalSetServiceAccountStatus(msg.sender, STATUS_NOT_JOINED);
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

  function _pushCoverageDemand(
    IInsurerPool target,
    uint256 amount
  ) private returns (bool) {
    return _addCoverageDemandTo(target, amount);
  }

  function _addCoverageDemandTo(IInsurerPool target, uint256 amount) private returns (bool) {
    uint256 unitSize = IInsurerPool(msg.sender).coverageUnitSize();
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
    internalCoverageDemandAdded(address(target), amountAdded);

    return amountAdded < amount;
  }

  function internalAllocateCoverageDemand(
    address target,
    uint256 amount,
    uint256 unitSize
  ) internal virtual returns (uint256 amountToAdd, uint256 premiumRate);

  function internalCoverageDemandAdded(address target, uint256 amount) internal virtual;

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual;

  function getAccountStatus(address account) internal view virtual returns (uint16);

  function internalIsAllowedHolder(uint16 status) internal view virtual returns (bool) {
    return status > 0 && status <= INDEX_MAX;
  }
}
