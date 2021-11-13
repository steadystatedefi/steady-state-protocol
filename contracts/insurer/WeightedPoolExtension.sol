// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsuredPool.sol';
import './WeightedPoolStorage.sol';

contract WeightedPoolExtension is InsurerJoinBase, IInsurerPoolDemand, WeightedPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(uint256 unitSize) InsurerPoolBase(address(0)) WeightedRoundsBase(unitSize) {}

  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external override {
    internalRequestJoin(insured);
  }

  function charteredDemand() public pure override(IInsurerPoolDemand, WeightedPoolStorage) returns (bool) {
    return true;
  }

  function coverageUnitSize() external view override returns (uint256) {
    return internalUnitSize();
  }

  function onCoverageDeclined(address insured) external override onlyCollateralFund {
    insured;
    Errors.notImplemented();
  }

  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external override onlyActiveInsured returns (uint256 addedCount) {
    // TODO access control
    AddCoverageDemandParams memory params;
    params.insured = msg.sender;
    require(premiumRate == (params.premiumRate = uint40(premiumRate)));
    params.loopLimit = ~params.loopLimit;
    hasMore;
    require(unitCount <= type(uint64).max);
    console.log('premiumRate', premiumRate);

    return unitCount - super.internalAddCoverageDemand(uint64(unitCount), params);
  }

  function cancelCoverageDemand(uint256 unitCount, bool hasMore)
    external
    override
    onlyActiveInsured
    returns (uint256 cancelledUnits)
  {
    unitCount;
    hasMore;
    Errors.notImplemented();
    return 0;
  }

  function getCoverageDemand(address insured)
    external
    view
    override
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    (coverage, , ) = internalGetCoveredDemand(params);
    return (params.receivedCoverage, coverage);
  }

  function receiveDemandedCoverage(address insured)
    external
    override
    onlyActiveInsured
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~params.loopLimit;

    coverage = internalUpdateCoveredDemand(params);

    // TODO transfer coverage?

    return (params.receivedCoverage, coverage);
  }

  function internalPrepareJoin(address insured) internal override {
    WeightedPoolParams memory params = _params;
    InsuredParams memory insuredParams = IInsuredPool(insured).insuredParams();

    uint256 maxShare = uint256(insuredParams.riskWeightPct).percentDiv(params.riskWeightTarget);
    if (maxShare >= params.maxInsuredShare) {
      maxShare = params.maxInsuredShare;
    } else if (maxShare < params.minInsuredShare) {
      maxShare = params.minInsuredShare;
    }

    super.internalSetInsuredParams(
      insured,
      Rounds.InsuredParams({minUnits: insuredParams.minUnitsPerInsurer, maxShare: uint16(maxShare)})
    );
  }

  function internalInitiateJoin(address insured) internal override returns (InsuredStatus) {
    if (_joinHandler == address(0)) return InsuredStatus.Joining;
    if (_joinHandler == address(this)) return InsuredStatus.Accepted;
    return IJoinHandler(_joinHandler).handleJoinRequest(insured);
  }

  function internalIsInvestor(address account)
    internal
    view
    override(InsurerJoinBase, WeightedPoolStorage)
    returns (bool)
  {
    return WeightedPoolStorage.internalIsInvestor(account);
  }

  function internalGetStatus(address account)
    internal
    view
    override(InsurerJoinBase, WeightedPoolStorage)
    returns (InsuredStatus)
  {
    return WeightedPoolStorage.internalGetStatus(account);
  }

  function internalSetStatus(address account, InsuredStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }

  function onTransferReceived(
    address,
    address,
    uint256,
    bytes memory
  ) external pure override returns (bytes4) {
    revert();
  }
}
