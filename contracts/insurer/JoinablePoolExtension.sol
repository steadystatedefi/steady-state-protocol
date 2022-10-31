// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IJoinable.sol';
import './WeightedPoolExtension.sol';
import './WeightedPoolStorage.sol';

/// @dev NB! MUST HAVE NO STORAGE
/// @dev This is a portion of implementation of a weighted-rounds-based insurer. It is introduced due to overcome the code size limit.
/// @dev This portion contains logic to handle joins of insureds, and to handle addition and cancellation of demand of insureds.
contract JoinablePoolExtension is WeightedPoolStorage, IJoinableBase, IDemandableCoverage {
  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedPoolConfig(acl, unitSize, collateral_) {}

  /// @return an access controller of this insurer
  function accessController() external view returns (IAccessController) {
    return remoteAcl();
  }

  /// @inheritdoc IJoinableBase
  function requestJoin(address insured) external override {
    Access.require(msg.sender == insured);
    internalRequestJoin(insured);
  }

  /// @dev Allows a governor or an INSURER_OPS to accept or reject joining of an insured.
  function approveJoiner(address insured, bool accepted) external onlyGovernorOr(AccessFlags.INSURER_OPS) {
    internalProcessJoin(insured, accepted);
  }

  /// @inheritdoc IJoinableBase
  function cancelJoin() external returns (MemberStatus) {
    return internalCancelJoin(msg.sender);
  }

  /// @inheritdoc IDemandableCoverage
  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  /// @inheritdoc IDemandableCoverage
  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore,
    uint256 loopLimit
  ) external override onlyActiveInsured returns (uint256 addedCount) {
    AddCoverageDemandParams memory params;
    params.insured = msg.sender;
    Arithmetic.require(premiumRate == (params.premiumRate = uint40(premiumRate)));
    params.loopLimit = defaultLoopLimit(LoopLimitType.AddCoverageDemand, loopLimit);
    params.hasMore = hasMore;
    Arithmetic.require(unitCount <= type(uint64).max);

    addedCount = unitCount - super.internalAddCoverageDemand(uint64(unitCount), params);
    //If there was excess coverage before adding this demand, immediately assign it
    if (_excessCoverage > 0 && internalCanAddCoverage()) {
      // avoid addCoverage code to be duplicated within WeightedPoolExtension to reduce contract size
      WeightedPoolBase(address(this)).pushCoverageExcess();
    }
    return addedCount;
  }

  /// @inheritdoc IDemandableCoverage
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
