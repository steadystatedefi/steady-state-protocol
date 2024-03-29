// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../interfaces/IWeightedPool.sol';
import '../interfaces/IPremiumSource.sol';
import '../tools/math/PercentageMath.sol';
import './WeightedRoundsBase.sol';
import './WeightedPoolAccessControl.sol';

/// @dev This template implements configurable strategies for weighted-rounds. See WeightedPoolParams
abstract contract WeightedPoolConfig is WeightedRoundsBase, WeightedPoolAccessControl {
  using PercentageMath for uint256;
  using WadRayMath for uint256;
  using Rounds for Rounds.PackedInsuredParams;

  /// @dev params for strategies
  WeightedPoolParams internal _params;
  /// @dev compacted loop limits (one limit type is 1 byte)
  uint256 internal _loopLimits;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedRoundsBase(unitSize) GovernedHelper(acl, collateral_) {}

  event WeightedPoolParamsUpdated(WeightedPoolParams params);

  /// @dev Validates and sets params
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
      params.coverageForepayPct >= _params.coverageForepayPct &&
        params.coverageForepayPct >= PercentageMath.HALF_ONE &&
        params.maxUserDrawdownPct <= PercentageMath.ONE - params.coverageForepayPct
    );

    _params = params;
    emit WeightedPoolParamsUpdated(params);
  }

  /// @inheritdoc WeightedRoundsBase
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

  /// @return a number of coverage units which are passive (not used for coverage), but can be considered to calculate risk weights.
  function internalGetPassiveCoverageUnits() internal view returns (uint256) {}

  /// @inheritdoc WeightedRoundsBase
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

  /// @inheritdoc WeightedRoundsBase
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

  /// @inheritdoc WeightedRoundsBase
  function internalIsEnoughForMore(Rounds.InsuredEntry memory entry, uint256 unitCount) internal view override returns (bool) {
    return _requiredForMinimumCoverage(entry.demandedUnits, entry.params.minUnits(), unitCount) || unitCount >= _params.minAdvanceUnits;
  }

  /// @dev Sets a default loop limit for the given op
  function setDefaultLoopLimit(LoopLimitType t, uint8 limit) internal {
    _loopLimits = (_loopLimits & ~(uint256(0xFF) << (uint8(t) << 3))) | (uint256(limit) << (uint8(t) << 3));
  }

  /// @dev Provides a loop limit for an operation
  /// @param t is a type of the operation
  /// @param limit is a custom limit, zero to request a default limit
  /// @return loop limit for the operation
  function defaultLoopLimit(LoopLimitType t, uint256 limit) internal view virtual returns (uint256) {
    if (limit == 0) {
      limit = uint8(_loopLimits >> (uint8(t) << 3));
      if (limit == 0) {
        limit = t <= LoopLimitType.ReceivableDemandedCoverage ? type(uint8).max : (t < LoopLimitType.PullDemandAfterJoin ? 31 : 0);
      }
      if (limit == type(uint8).max) {
        limit = type(uint256).max;
      }
    }
    return limit;
  }

  /// @dev Gets approved params for the insured from the ApprovalCatalog.
  /// @return ok is true when an approved policy is available for the `insured`
  /// @return data with risk and premium data from the approved policy of the `insured`
  function internalDefaultUnderwrittenParams(address insured) internal view returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    IApprovalCatalog ac = approvalCatalog();
    if (address(ac) != address(0)) {
      (ok, data) = ac.getAppliedApplicationForInsurer(insured);
    }
  }

  /// @dev Gets approved params for the insured from the governor, or from the ApprovalCatalog when the governor doesn't support IInsurerGovernor.
  /// @return ok is true when an approved policy is available for the `insured`
  /// @return data with risk and premium data from the approved policy of the `insured`
  function internalGetUnderwrittenParams(address insured) internal virtual returns (bool ok, IApprovalCatalog.ApprovedPolicyForInsurer memory data) {
    IInsurerGovernor g = governorContract();
    return address(g) != address(0) ? g.getApprovedPolicyForInsurer(insured) : internalDefaultUnderwrittenParams(insured);
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

    openCollateralSubBalance(insured);

    return true;
  }

  event ParamsForInsuredUpdated(address indexed insured, Rounds.InsuredParams params);

  function internalAfterJoinOrLeave(address insured, MemberStatus status) internal virtual override {
    if (status == MemberStatus.Accepted) {
      uint256 loopLimit = defaultLoopLimit(LoopLimitType.PullDemandAfterJoin, 0);
      if (loopLimit > 0) {
        IInsuredPool(insured).pullCoverageDemand(0, type(uint256).max, loopLimit);
      }
    }
  }

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

  function openCollateralSubBalance(address recipient) internal {
    ISubBalance(collateral()).openSubBalance(recipient);
  }

  function closeCollateralSubBalance(address recipient, uint256 transferAmount) internal {
    ISubBalance(collateral()).closeSubBalance(recipient, transferAmount);
  }

  function balanceOfGivenOutCollateral(address account) internal view returns (uint256 u) {
    (, u, ) = ISubBalance(collateral()).balancesOf(account);
  }

  function subBalanceOfCollateral(address account) internal view returns (uint256) {
    return ISubBalance(collateral()).subBalanceOf(account, address(this));
  }
}

/// @dev Type of operation to get the default loop limit for
enum LoopLimitType {
  // View ops (255 iterations by default)
  ReceivableDemandedCoverage,
  // Modify ops (31 iterations by default)
  AddCoverageDemand,
  AddCoverage,
  AddCoverageDemandByPull,
  CancelCoverageDemand,
  ReceiveDemandedCoverage,
  // Modify ops (0 by default)
  PullDemandAfterJoin
}
