// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../ImperpetualPoolBase.sol';
import './MockWeightedRounds.sol';

contract MockImperpetualPool is IInsurerGovernor, ImperpetualPoolBase {
  constructor(
    address collateral_,
    uint256 unitSize,
    uint8 decimals,
    ImperpetualPoolExtension extension
  )
    ERC20DetailsBase('ImperpetualPoolToken', '$IC', decimals)
    ImperpetualPoolBase(IAccessController(address(0)), unitSize, extension)
    Collateralized(collateral_)
  {
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
        maxDrawdownInverse: 9000 // 90%
      })
    );
  }

  function handleJoinRequest(address) external pure override returns (InsuredStatus) {
    return InsuredStatus.Accepted;
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
}
