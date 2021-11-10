// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import './InsuredBalancesBase.sol';

abstract contract InsuredJoinBase is IInsuredPool {
  address[] private _insurers; // IInsurerPool[]

  uint16 private constant STATUS_MAX = type(uint16).max;
  uint16 private constant STATUS_UNKNOWN = STATUS_MAX;
  uint16 private constant STATUS_PENDING = STATUS_MAX - 1;
  uint16 private constant STATUS_ACCEPTED = STATUS_MAX - 2;

  uint16 private constant INDEX_MAX = STATUS_MAX - 16;

  modifier onlyAdmin() virtual {
    _;
  }

  function joinPool(IInsurerPool pool) external onlyAdmin {
    require(address(pool) != address(0));
    uint32 status = getAccountStatus(address(pool));

    require(status == 0 || status == STATUS_UNKNOWN);
    internalSetServiceAccountStatus(msg.sender, STATUS_PENDING);

    pool.requestJoin(address(this));
  }

  function getInsurers() public view returns (address[] memory) {
    return _insurers;
  }

  function joinProcessed(bool accepted) external override {
    uint32 status = getAccountStatus(msg.sender);
    if (status != STATUS_PENDING) {
      require(status == STATUS_ACCEPTED);
      return;
    }
    if (!accepted) {
      internalSetServiceAccountStatus(msg.sender, STATUS_UNKNOWN);
      return;
    }

    _pushCoverageDemand(IInsurerPool(msg.sender), STATUS_ACCEPTED, 0);
  }

  function pullCoverageDemand() external override returns (bool) {
    uint16 status = getAccountStatus(msg.sender);
    if (status > INDEX_MAX) {
      return false;
    }

    require(status > 0);
    return _pushCoverageDemand(IInsurerPool(msg.sender), status, 0) <= INDEX_MAX;
  }

  function pushCoverageDemandTo(IInsurerPool target, uint256 amount) external onlyAdmin {
    uint16 status = getAccountStatus(address(target));
    if (status != STATUS_ACCEPTED) {
      require(status > 0 && status <= INDEX_MAX);
      _pushCoverageDemand(target, status, amount);
    } else {
      _pushCoverageDemand(target, 0, amount);
    }
  }

  function _pushCoverageDemand(
    IInsurerPool target,
    uint16 index,
    uint256 amount
  ) private returns (uint16) {
    if (_addCoverageDemandTo(target, amount)) {
      if (index > 0 && index <= INDEX_MAX) {
        return index;
      }

      require(index == STATUS_ACCEPTED);
      require(_insurers.length < INDEX_MAX);
      _insurers.push(address(target));
      index = uint16(_insurers.length);
    } else if (index == 0) {
      return 0;
    } else if (index != STATUS_ACCEPTED) {
      require(index <= INDEX_MAX);

      address last = _insurers[_insurers.length - 1];
      _insurers.pop();

      if (last != address(target)) {
        internalSetServiceAccountStatus(last, index);
      }
      index = STATUS_ACCEPTED;
    }

    internalSetServiceAccountStatus(address(target), index);
    return index;
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
    return status <= STATUS_ACCEPTED;
  }
}
