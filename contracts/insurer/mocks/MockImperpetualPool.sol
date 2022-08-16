// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../ImperpetualPoolBase.sol';
import './MockWeightedRounds.sol';

contract MockImperpetualPool is IInsurerGovernor, ImperpetualPoolBase {
  constructor(ImperpetualPoolExtension extension, JoinablePoolExtension joinExtension)
    ERC20DetailsBase('ImperpetualPoolToken', '$IC', 18)
    ImperpetualPoolBase(extension, joinExtension)
  {
    internalSetTypedGovernor(this);
    internalSetPoolParams(
      WeightedPoolParams({
        maxAdvanceUnits: 10000,
        minAdvanceUnits: 1000,
        riskWeightTarget: 1000, // 10%
        minInsuredSharePct: 100, // 1%
        maxInsuredSharePct: 4000, // 40%
        minUnitsPerRound: 20,
        maxUnitsPerRound: 20,
        overUnitsPerRound: 30,
        coveragePrepayPct: 9000, // 90%
        maxUserDrawdownPct: 1000, // 10%
        unitsPerAutoPull: 0
      })
    );
  }

  function getRevision() internal pure override returns (uint256) {}

  function handleJoinRequest(address) external pure override returns (MemberStatus) {
    return MemberStatus.Accepted;
  }

  function governerQueryAccessControlMask(address, uint256 filterMask) external pure override returns (uint256) {
    return filterMask;
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return internalGetTotals(type(uint256).max);
  }

  function getExcessCoverage() external view returns (uint256) {
    return _excessCoverage;
  }

  function setExcessCoverage(uint256 v) external {
    internalSetExcess(v);
  }

  function internalOnCoverageRecovered() internal override {}

  // function dump() external view returns (Dump memory) {
  //   return _dump();
  // }

  // function dumpInsured(address insured)
  //   external
  //   view
  //   returns (
  //     Rounds.InsuredEntry memory,
  //     Rounds.Demand[] memory,
  //     Rounds.Coverage memory,
  //     Rounds.CoveragePremium memory
  //   )
  // {
  //   return _dumpInsured(insured);
  // }

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

  modifier onlyPremiumDistributor() override {
    _;
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

  function getApprovedPolicyForInsurer(address) external override returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    data.riskLevel = _riskWeightValue;
    if (data.riskLevel > 0) {
      _riskWeightValue = 0;
      data.riskLevel--;
      ok = true;
    }
  }
}
