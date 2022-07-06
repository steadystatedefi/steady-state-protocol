// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../PerpetualPoolBase.sol';
import './MockWeightedRounds.sol';

contract MockPerpetualPool is IInsurerGovernor, PerpetualPoolBase {
  constructor(
    address collateral_,
    uint256 unitSize,
    uint8 decimals,
    PerpetualPoolExtension extension
  ) ERC20DetailsBase('PerpetualPoolToken', '$IC', decimals) PerpetualPoolBase(IAccessController(address(0)), unitSize, collateral_, extension) {
    internalSetTypedGovernor(this);
    internalSetPoolParams(
      WeightedPoolParams({
        maxAdvanceUnits: 10000,
        minAdvanceUnits: 1000,
        riskWeightTarget: 1000, // 10%
        minInsuredShare: 100, // 1%
        maxInsuredShare: 4000, // 25%
        minUnitsPerRound: 20,
        maxUnitsPerRound: 20,
        overUnitsPerRound: 30,
        maxDrawdownInverse: 10000 // 100%
      })
    );
  }

  function handleJoinRequest(address) external pure override returns (InsuredStatus) {
    return InsuredStatus.Accepted;
  }

  function governerQueryAccessControlMask(address, uint256 filterMask) external pure returns (uint256) {
    return filterMask;
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals(type(uint256).max);
  }

  function getExcessCoverage() external view returns (uint256) {
    return _excessCoverage;
  }

  function setExcessCoverage(uint256 v) external {
    _excessCoverage = v;
  }

  function internalOnCoverageRecovered() internal override {}

  function dump() external view returns (Dump memory) {
    return _dump();
  }

  function getPendingAdjustments()
    external
    view
    returns (
      uint256 total,
      uint256 pendingCovered,
      uint256 pendingDemand
    )
  {
    return internalGetUnadjustedUnits();
  }

  function applyPendingAdjustments() external {
    internalApplyAdjustmentsToTotals();
  }

  function hasAnyAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function hasAllAcl(address, uint256) internal pure override returns (bool) {
    return true;
  }

  function isAdmin(address) internal pure override returns (bool) {
    return true;
  }

  uint16 private _riskWeightValue;

  function approveNextJoin(uint16 riskWeightValue) external {
    _riskWeightValue = riskWeightValue + 1;
  }

  function verifyPayoutRatio(address, uint256 payoutRatio) external pure override returns (uint256) {
    return payoutRatio;
  }

  function getApprovedPolicyForInsurer(address) external returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    data.riskLevel = _riskWeightValue;
    if (data.riskLevel > 0) {
      _riskWeightValue = 0;
      data.riskLevel--;
      ok = true;
    }
  }
}
