// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IJoinable.sol';
import './WeightedPoolExtension.sol';
import './WeightedPoolStorage.sol';

contract JoinablePoolExtension is IJoinableBase, ICancellableCoverageDemand, WeightedPoolStorage {
  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedPoolConfig(acl, unitSize, collateral_) {}

  function accessController() external view returns (IAccessController) {
    return remoteAcl();
  }

  function requestJoin(address insured) external override {
    Access.require(msg.sender == insured);
    internalRequestJoin(insured);
  }

  function approveJoiner(address insured, bool accepted) external onlyGovernorOr(AccessFlags.INSURER_OPS) {
    internalProcessJoin(insured, accepted);
  }

  function cancelJoin() external returns (MemberStatus) {
    return internalCancelJoin(msg.sender);
  }

  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  function cancelCoverageDemand(
    address insured,
    uint256 unitCount,
    uint256 loopLimit
  ) external override onlyActiveInsuredOrOps(insured) returns (uint256 cancelledUnits, uint256[] memory) {
    CancelCoverageDemandParams memory params;
    params.insured = insured;
    params.loopLimit = defaultLoopLimit(LoopLimitType.CancelCoverageDemand, loopLimit);

    if (unitCount > type(uint64).max) {
      unitCount = type(uint64).max;
    }
    cancelledUnits = internalCancelCoverageDemand(uint64(unitCount), params);
    return (cancelledUnits, params.rateBands);
  }
}
