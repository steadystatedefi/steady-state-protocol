// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../PerpetualPoolBase.sol';
import './MockWeightedRounds.sol';
import './IMockInsurer.sol';

contract MockPerpetualPool is IInsurerGovernor, PerpetualPoolBase {
  constructor(PerpetualPoolExtension extension, JoinablePoolExtension joinExtension)
    ERC20DetailsBase('PerpetualPoolToken', '$IC', 18)
    PerpetualPoolBase(extension, joinExtension)
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
        coverageForepayPct: 10000, // 100%
        maxUserDrawdownPct: 0, // 0%
        unitsPerAutoPull: 0
      })
    );
    setDefaultLoopLimit(LoopLimitType.PullDemandAfterJoin, 255);
  }

  function getRevision() internal pure override returns (uint256) {}

  function handleJoinRequest(address) external pure override returns (MemberStatus) {
    return MemberStatus.Accepted;
  }

  function governorQueryAccessControlMask(address, uint256 filterMask) external pure override returns (uint256, uint256) {
    return (filterMask, 0);
  }

  function getExcessCoverage() external view returns (uint256) {
    return _excessCoverage;
  }

  function setExcessCoverage(uint256 v) external {
    internalSetExcess(v);
  }

  function internalOnCoverageRecovered() internal override {}

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
  address private _expectedPremiumToken;

  function approveNextJoin(uint16 riskWeightValue, address expectedPremiumToken) external {
    _riskWeightValue = riskWeightValue + 1;
    _expectedPremiumToken = expectedPremiumToken;
  }

  function verifyPayoutRatio(address, uint256 payoutRatio) external pure override returns (uint256) {
    return payoutRatio;
  }

  function getApprovedPolicyForInsurer(address insured) external override returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    (ok, data) = internalDefaultUnderwrittenParams(insured);
    if (!ok) {
      data.riskLevel = _riskWeightValue;
      if (data.riskLevel > 0) {
        _riskWeightValue = 0;
        data.riskLevel--;
        data.premiumToken = _expectedPremiumToken;
        ok = true;
      }
    }
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return IMockInsurer(address(this)).getTotals(0);
  }
}
