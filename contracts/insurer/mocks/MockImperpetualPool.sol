// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../ImperpetualPoolBase.sol';
import './MockWeightedRounds.sol';
import './IMockInsurer.sol';

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
        coverageForepayPct: 9000, // 90%
        maxUserDrawdownPct: 1000, // 10%
        unitsPerAutoPull: 0
      })
    );
    setDefaultLoopLimit(LoopLimitType.PullDemandAfterJoin, 255);
  }

  function setCoverageForepayPct(uint16 pct) external {
    _params.coverageForepayPct = pct;
  }

  function getRevision() internal pure override returns (uint256) {}

  function handleJoinRequest(address) external pure virtual override returns (MemberStatus) {
    return MemberStatus.Accepted;
  }

  function governerQueryAccessControlMask(address, uint256 filterMask) external pure override returns (uint256) {
    return filterMask;
  }

  function getExcessCoverage() external view returns (uint256) {
    return _excessCoverage;
  }

  function setExcessCoverage(uint256 v) external {
    internalSetExcess(v);
  }

  function internalOnCoverageRecovered() internal override {}

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
  address private _expectedPremiumToken;

  function approveNextJoin(uint16 riskWeightValue, address expectedPremiumToken) external {
    _riskWeightValue = riskWeightValue + 1;
    _expectedPremiumToken = expectedPremiumToken;
  }

  function verifyPayoutRatio(address, uint256 payoutRatio) external pure override returns (uint256) {
    return payoutRatio;
  }

  function getApprovedPolicyForInsurer(address) external override returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    data.riskLevel = _riskWeightValue;
    if (data.riskLevel > 0) {
      _riskWeightValue = 0;
      data.riskLevel--;
      data.premiumToken = _expectedPremiumToken;
      ok = true;
    }
  }

  function getTotals() external view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    return IMockInsurer(address(this)).getTotals(0);
  }
}
