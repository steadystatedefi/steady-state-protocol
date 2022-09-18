// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../interfaces/IWeightedPool.sol';
import '../interfaces/IPremiumSource.sol';
import '../tools/math/PercentageMath.sol';
import './WeightedRoundsBase.sol';
import './WeightedPoolAccessControl.sol';

abstract contract WeightedPoolConfig is WeightedRoundsBase, WeightedPoolAccessControl {
  using PercentageMath for uint256;
  using WadRayMath for uint256;
  using Rounds for Rounds.PackedInsuredParams;

  WeightedPoolParams internal _params;

  // uint256 private _loopLimits;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedRoundsBase(unitSize) GovernedHelper(acl, collateral_) {}

  // function internalSetLoopLimits(uint16[] memory limits) internal virtual {
  //   uint256 v;
  //   for (uint256 i = limits.length; i > 0; ) {
  //     i--;
  //     v = (v << 16) | uint16(limits[i]);
  //   }
  //   _loopLimits = v;
  // }

  event WeightedPoolParamsUpdated(WeightedPoolParams params);

  function internalSetPoolParams(WeightedPoolParams memory params) internal virtual {
    Value.require(
      params.minUnitsPerRound > 0 && params.maxUnitsPerRound >= params.minUnitsPerRound && params.overUnitsPerRound >= params.maxUnitsPerRound
    );

    Value.require(params.maxAdvanceUnits >= params.minAdvanceUnits && params.minAdvanceUnits >= params.maxUnitsPerRound);

    Value.require(
      params.minInsuredSharePct > 0 && params.maxInsuredSharePct > params.minInsuredSharePct && params.maxInsuredSharePct <= PercentageMath.ONE
    );

    Value.require(params.riskWeightTarget > 0 && params.riskWeightTarget < PercentageMath.ONE);

    Value.require(
      params.coveragePrepayPct >= _params.coveragePrepayPct &&
        params.coveragePrepayPct >= PercentageMath.HALF_ONE &&
        params.maxUserDrawdownPct <= PercentageMath.ONE - params.coveragePrepayPct
    );

    _params = params;
    emit WeightedPoolParamsUpdated(params);
  }

  ///@return The number of rounds to initialize a new batch
  function internalBatchAppend(uint32 openRounds, uint64 unitCount) internal view override returns (uint24) {
    uint256 max = _params.maxUnitsPerRound;
    uint256 min = _params.minAdvanceUnits / max;
    max = _params.maxAdvanceUnits / max;

    if (min > type(uint24).max) {
      if (openRounds + min > max) {
        return 0;
      }
      min = type(uint24).max;
    }

    if (openRounds + min > max) {
      if (min < (max >> 1) || openRounds > (max >> 1)) {
        return 0;
      }
    }

    if (unitCount > type(uint24).max) {
      unitCount = type(uint24).max;
    }

    if ((unitCount /= uint64(min)) <= 1) {
      return uint24(min);
    }

    if ((max = (max - openRounds) / min) < unitCount) {
      min *= max;
    } else {
      min *= unitCount;
    }
    Sanity.require(min > 0);

    return uint24(min);
  }

  function internalGetPassiveCoverageUnits() internal view returns (uint256) {}

  /// @dev Calculate the limits of the number of units that can be added to a round
  function internalRoundLimits(
    uint80 totalUnitsBeforeBatch,
    uint24 batchRounds,
    uint16 unitPerRound,
    uint64 demandedUnits,
    uint16 maxShare
  )
    internal
    view
    override
    returns (
      uint16, // maxShareUnitsPerRound,
      uint16, // minUnitsPerRound,
      uint16, // readyUnitsPerRound
      uint16 // maxUnitsPerRound
    )
  {
    (uint16 minUnitsPerRound, uint16 maxUnitsPerRound) = (_params.minUnitsPerRound, _params.maxUnitsPerRound);

    // total # of units could be allocated when this round if full
    uint256 x = uint256(unitPerRound < minUnitsPerRound ? minUnitsPerRound : unitPerRound + 1) *
      batchRounds +
      totalUnitsBeforeBatch +
      internalGetPassiveCoverageUnits();

    // max of units that can be added in total for the share not to be exceeded
    x = x.percentMul(maxShare);

    if (x < demandedUnits + batchRounds) {
      x = 0;
    } else {
      unchecked {
        x = (x - demandedUnits) / batchRounds;
      }
      if (unitPerRound + x >= maxUnitsPerRound) {
        if (unitPerRound < minUnitsPerRound) {
          // this prevents lockup of a batch when demand is added by small portions
          minUnitsPerRound = unitPerRound + 1;
        }
      }

      if (x > type(uint16).max) {
        x = type(uint16).max;
      }
    }

    return (uint16(x), minUnitsPerRound, maxUnitsPerRound, _params.overUnitsPerRound);
  }

  function _requiredForMinimumCoverage(
    uint64 demandedUnits,
    uint64 minUnits,
    uint256 remainingUnits
  ) private pure returns (bool) {
    return demandedUnits < minUnits && demandedUnits + remainingUnits >= minUnits;
  }

  function internalBatchSplit(
    uint64 demandedUnits,
    uint64 minUnits,
    uint24 batchRounds,
    uint24 remainingUnits
  ) internal pure override returns (uint24 splitRounds) {
    // console.log('internalBatchSplit-0', demandedUnits, minUnits);
    // console.log('internalBatchSplit-1', batchRounds, remainingUnits);
    return _requiredForMinimumCoverage(demandedUnits, minUnits, remainingUnits) || (remainingUnits > batchRounds >> 2) ? remainingUnits : 0;
  }

  function internalIsEnoughForMore(Rounds.InsuredEntry memory entry, uint256 unitCount) internal view override returns (bool) {
    return _requiredForMinimumCoverage(entry.demandedUnits, entry.params.minUnits(), unitCount) || unitCount >= _params.minAdvanceUnits;
  }

  function defaultLoopLimit(LoopLimitType t, uint256 limit) internal view returns (uint256) {
    if (limit == 0) {
      // limit = uint16(_loopLimits >> (uint8(t) << 1));
      // if (limit == 0) {
      limit = t > LoopLimitType.ReceivableDemandedCoverage ? 31 : 255;
      // }
    }
    this;
    return limit;
  }

  function internalGetUnderwrittenParams(address insured) internal virtual returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    IApprovalCatalog ac = approvalCatalog();
    if (address(ac) != address(0)) {
      (ok, data) = ac.getAppliedApplicationForInsurer(insured);
    } else {
      IInsurerGovernor g = governorContract();
      if (address(g) != address(0)) {
        (ok, data) = g.getApprovedPolicyForInsurer(insured);
      }
    }
  }

  /// @dev Prepare for an insured pool to join by setting the parameters
  function internalPrepareJoin(address insured) internal override returns (bool) {
    (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory approvedParams) = internalGetUnderwrittenParams(insured);
    if (!ok) {
      return false;
    }

    uint256 maxShare = approvedParams.riskLevel == 0 ? PercentageMath.ONE : uint256(_params.riskWeightTarget).percentDiv(approvedParams.riskLevel);
    uint256 v;
    if (maxShare >= (v = _params.maxInsuredSharePct)) {
      maxShare = v;
    } else if (maxShare < (v = _params.minInsuredSharePct)) {
      maxShare = v;
    }

    if (maxShare == 0) {
      return false;
    }

    State.require(IPremiumSource(insured).premiumToken() == approvedParams.premiumToken);

    InsuredParams memory insuredSelfParams = IInsuredPool(insured).insuredParams();

    uint256 unitSize = internalUnitSize();
    uint256 minUnits = (insuredSelfParams.minPerInsurer + unitSize - 1) / unitSize;
    Arithmetic.require(minUnits <= type(uint24).max);

    uint256 baseRate = (approvedParams.basePremiumRate + unitSize - 1) / unitSize;
    Arithmetic.require(baseRate <= type(uint40).max);

    Rounds.InsuredParams memory params = Rounds.InsuredParams({
      minUnits: uint24(minUnits),
      maxShare: uint16(maxShare),
      minPremiumRate: uint40(baseRate)
    });

    super.internalSetInsuredParams(insured, params);
    emit ParamsForInsuredUpdated(insured, params);

    return true;
  }

  event ParamsForInsuredUpdated(address indexed insured, Rounds.InsuredParams params);

  function internalGetStatus(address account) internal view override returns (MemberStatus) {
    return internalGetInsuredStatus(account);
  }

  function internalSetStatus(address account, MemberStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function internalStatusOf(address account) internal view returns (MemberStatus status) {
    if ((status = internalGetStatus(account)) == MemberStatus.Unknown && internalIsInvestor(account)) {
      status = MemberStatus.NotApplicable;
    }
    return status;
  }
}

enum LoopLimitType {
  // View ops (255 iterations by default)
  ReceivableDemandedCoverage,
  // Modify ops (31 iterations by default)
  AddCoverageDemand,
  AddCoverage,
  AddCoverageDemandByPull,
  CancelCoverageDemand,
  ReceiveDemandedCoverage
}
