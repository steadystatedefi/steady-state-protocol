// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';

import 'hardhat/console.sol';

abstract contract InsuredPoolBase is IInsuredPool, InsuredBalancesBase, InsuredJoinBase {
  uint256 private _totalDemand;
  uint64 private _premiumRate;
  InsuredParams private _params;

  constructor(uint256 totalDemand, uint64 premiumRate) {
    _totalDemand = totalDemand;
    _premiumRate = premiumRate;
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

  function internalIsAllowedHolder(uint16 status)
    internal
    view
    override(InsuredBalancesBase, InsuredJoinBase)
    returns (bool)
  {
    return InsuredJoinBase.internalIsAllowedHolder(status);
  }

  function internalCoverageDemandAdded(address target, uint256 amount) internal override {
    console.log('internalCoverageDemandAdded', target, amount, _totalDemand);
    _totalDemand -= amount;
    InsuredBalancesBase.internalMint(target, amount, address(0));
  }

  function internalHandleDirectInvestment(
    uint256 amount,
    uint256 minAmount,
    uint256
  ) internal override returns (uint256 availableAmount, uint64 premiumRate) {
    availableAmount = _totalDemand;
    if (availableAmount > amount) {
      _totalDemand = availableAmount - amount;
      availableAmount = amount;
    } else if (availableAmount > 0 && availableAmount >= minAmount) {
      _totalDemand = 0;
    } else {
      availableAmount = 0;
    }
    return (availableAmount, _premiumRate);
  }

  function internalAllocateCoverageDemand(
    address target,
    uint256 amount,
    uint256 unitSize
  ) internal view override returns (uint256 amountToAdd, uint256 premiumRate) {
    console.log('internalAllocateCoverageDemand', target, amount, unitSize);
    console.log('internalAllocateCoverageDemand', _totalDemand, _premiumRate);
    target;
    amount;
    unitSize;
    return (_totalDemand, _premiumRate);
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
}
