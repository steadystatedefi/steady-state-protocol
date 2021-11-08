// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import './InsuredBalancesBase.sol';
import './InsuredJoinBase.sol';

abstract contract InsuredPoolBase is IInsuredPool, InsuredBalancesBase, InsuredJoinBase {
  function internalSetServiceAccountStatus(address account, uint32 status)
    internal
    override(InsuredBalancesBase, InsuredJoinBase)
  {
    return InsuredBalancesBase.internalSetServiceAccountStatus(account, status);
  }

  function getAccountStatus(address account)
    internal
    view
    override(InsuredBalancesBase, InsuredJoinBase)
    returns (uint32)
  {
    return InsuredBalancesBase.getAccountStatus(account);
  }

  function internalIsAllowedHolder(uint32 status)
    internal
    view
    override(InsuredBalancesBase, InsuredJoinBase)
    returns (bool)
  {
    return InsuredJoinBase.internalIsAllowedHolder(status);
  }

  //   function internalAllocateCoverageDemand(address target, uint256 amount, uint256 unitSize) internal virtual
  //     returns (uint256 amountToAdd, uint256 premiumRate);

  function internalCoverageDemandAdded(address target, uint256 amount) internal override {
    InsuredBalancesBase.internalMint(target, amount, address(0));
  }

  //   function internalInvest(
  //     uint256 amount,
  //     uint256 minAmount,
  //     uint256 minPremiumRate
  //   ) internal virtual returns (uint256 availableAmount, uint64 premiumRate);
}
