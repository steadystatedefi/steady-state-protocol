// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/Math.sol';
import '../libraries/Arrays.sol';
import '../interfaces/IInsurerPool.sol';
import './Rounds.sol';

import 'hardhat/console.sol';

/// @title A calculator for allocating coverage
/// @notice Coverage is demanded and provided through rounds and batches.
// solhint-disable-next-line max-states-count
abstract contract WeightedRoundsBase {
  using Rounds for Rounds.Batch;
  using Rounds for Rounds.State;
  using Rounds for Rounds.PackedInsuredParams;
  using EnumerableSet for EnumerableSet.AddressSet;
  using WadRayMath for uint256;
  using Math for uint256;

  uint256 private immutable _unitSize;

  constructor(uint256 unitSize) {
    Value.require(unitSize > 0);
    _unitSize = unitSize;
  }

  /// @dev tracking info about insured pools
  mapping(address => Rounds.InsuredEntry) private _insureds;
  /// @dev demand log of each insured pool, updated by addition of coverage demand
  mapping(address => Rounds.Demand[]) private _demands;
  /// @dev coverage summary of each insured pool, updated by retrieving collected coverage
  mapping(address => Rounds.Coverage) private _covered;
  /// @dev premium summary of each insured pool, updated by retrieving collected coverage
  mapping(address => Rounds.CoveragePremium) private _premiums;

  /// @dev one way linked list of batches, appended by adding coverage demand, trimmed by adding coverage
  mapping(uint64 => Rounds.Batch) private _batches;

  /// @dev total number of batches
  uint64 private _batchCount;
  /// @dev the most recently added batch (head of the linked list)
  uint64 private _latestBatchNo;
  /// @dev points to an earliest round that is open, can not be zero
  uint64 private _firstOpenBatchNo;
  /// @dev number of open rounds starting from the partial one to _latestBatchNo
  /// @dev it is provided to the logic distribution control logic
  uint32 private _openRounds;
  /// @dev summary of total pool premium (covers all batches before the partial)
  Rounds.CoveragePremium private _poolPremium;

  struct PartialState {
    /// @dev amount of coverage in the partial round, must be zero when roundNo == batch size
    uint128 roundCoverage;
    /// @dev points either to a partial round or to the last full round when there is no other rounds
    /// @dev can ONLY be zero when there is no rounds (zero state)
    uint64 batchNo;
    /// @dev number of a partial round / also is the number of full rounds in the batch
    /// @dev when equals to batch size - then there is no partial round
    uint24 roundNo;
  }
  /// @dev the batch being filled (partially filled)
  PartialState private _partial;

  /// @dev segment of a coverage integral (time-weighted) for a partial or full batch
  struct TimeMark {
    /// @dev value of integral of coverage for a batch
    uint192 coverageTW;
    /// @dev last updated at
    uint32 timestamp;
    /// @dev time duration of this batch (length of the integral segment)
    uint32 duration;
  }
  /// @dev segments of coverage integral NB! Each segment is independent, it does NOT include / cosider previous segments
  mapping(uint64 => TimeMark) private _marks;

  uint80 private _pendingCancelledCoverageUnits;
  uint80 private _pendingCancelledDemandUnits;

  /// @dev a batch number to look for insureds with "hasMore" in _pullableDemands
  uint64 private _pullableBatchNo;
  /// @dev sets of insureds with "hasMore"
  mapping(uint64 => EnumerableSet.AddressSet) private _pullableDemands;

  function internalSetInsuredStatus(address account, MemberStatus status) internal {
    _insureds[account].status = status;
  }

  function internalGetInsuredStatus(address account) internal view returns (MemberStatus) {
    return _insureds[account].status;
  }

  ///@dev Sets the minimum amount of units this insured pool will assign and the max share % of the pool it can take up
  function internalSetInsuredParams(address account, Rounds.InsuredParams memory params) internal {
    _insureds[account].params = Rounds.packInsuredParams(params.minUnits, params.maxShare, params.minPremiumRate);
  }

  function internalGetInsuredParams(address account) internal view returns (MemberStatus, Rounds.InsuredParams memory) {
    Rounds.InsuredEntry storage entry = _insureds[account];
    return (entry.status, entry.params.unpackInsuredParams());
  }

  function internalUnitSize() internal view returns (uint256) {
    return _unitSize;
  }

  struct AddCoverageDemandParams {
    uint256 loopLimit;
    address insured;
    uint40 premiumRate;
    bool hasMore;
    // temporary variables
    uint64 prevPullBatch;
    bool takeNext;
  }

  /// @dev Adds coverage demand by performing the following:
  /// @dev Find which batch to first append to
  /// @dev Fill the batch, and create new batches if needed, looping under either all units added to batch or loopLimit
  /// @return The remaining demanded units
  function internalAddCoverageDemand(uint64 unitCount, AddCoverageDemandParams memory params)
    internal
    returns (
      uint64 // remainingCount
    )
  {
    // console.log('\ninternalAddCoverageDemand', unitCount);
    Rounds.InsuredEntry memory entry = _insureds[params.insured];
    Access.require(entry.status == MemberStatus.Accepted);
    Value.require(entry.params.minPremiumRate() <= params.premiumRate);

    if (unitCount == 0 || params.loopLimit == 0) {
      return unitCount;
    }

    Rounds.Demand[] storage demands = _demands[params.insured];
    params.prevPullBatch = entry.nextBatchNo;

    (Rounds.Batch memory b, uint64 thisBatch, bool isFirstOfOpen) = _findBatchToAppend(entry.nextBatchNo);

    Rounds.Demand memory demand;
    uint32 openRounds = _openRounds - _partial.roundNo;
    bool updateBatch;
    for (;;) {
      // console.log('addDemandLoop', thisBatch, isFirstOfOpen, b.totalUnitsBeforeBatch);
      params.loopLimit--;

      // Sanity.require(thisBatch != 0);
      if (b.rounds == 0) {
        // NB! empty batches can also be produced by cancellation

        b.rounds = internalBatchAppend(_adjustedTotalUnits(b.totalUnitsBeforeBatch), openRounds, unitCount);
        // console.log('addDemandToEmpty', b.rounds, openRounds - _partial.roundNo);

        if (b.rounds == 0) {
          break;
        }

        openRounds += b.rounds;
        _initTimeMark(_latestBatchNo = b.nextBatchNo = ++_batchCount);
        updateBatch = true;
      }

      uint16 addPerRound;
      if (b.isOpen()) {
        (addPerRound, params.takeNext) = _addToBatch(unitCount, b, entry, params, isFirstOfOpen);
        // console.log('addToBatchResult', addPerRound, takeNext);
        if (addPerRound > 0) {
          updateBatch = true;
        } else if (b.unitPerRound == 0) {
          updateBatch = false;
          break;
        }

        if (isFirstOfOpen && b.isOpen()) {
          _firstOpenBatchNo = thisBatch;
          isFirstOfOpen = false;
        }
      }

      if (b.rounds > 0 && _addToSlot(demand, demands, addPerRound, b.rounds, params.premiumRate)) {
        demand = Rounds.Demand({startBatchNo: thisBatch, premiumRate: params.premiumRate, rounds: b.rounds, unitPerRound: addPerRound});
      }

      if (addPerRound > 0) {
        // Sanity.require(takeNext);
        uint64 addedUnits = uint64(addPerRound) * b.rounds;
        unitCount -= addedUnits;
        entry.demandedUnits += addedUnits;
      }

      if (!params.takeNext) {
        break;
      }

      _batches[thisBatch] = b;
      updateBatch = false;

      entry.nextBatchNo = thisBatch = b.nextBatchNo;
      // Sanity.require(thisBatch != 0);

      uint80 totalUnitsBeforeBatch = b.totalUnitsBeforeBatch + uint80(b.unitPerRound) * b.rounds;
      b = _batches[thisBatch];

      if (b.totalUnitsBeforeBatch != totalUnitsBeforeBatch) {
        b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
        updateBatch = true;
      }

      if (unitCount == 0 || params.loopLimit == 0) {
        break;
      }
    }

    if (updateBatch) {
      _batches[thisBatch] = b;
    }
    _openRounds = openRounds + _partial.roundNo;

    _setPullBatch(params, params.hasMore || internalIsEnoughForMore(entry, unitCount) ? thisBatch : 0);
    _insureds[params.insured] = entry;

    if (demand.unitPerRound != 0) {
      demands.push(demand);
    }

    if (isFirstOfOpen) {
      _firstOpenBatchNo = thisBatch;
    }

    return unitCount;
  }

  function internalIsEnoughForMore(Rounds.InsuredEntry memory entry, uint256 unitCount) internal view virtual returns (bool);

  function _setPullBatch(AddCoverageDemandParams memory params, uint64 newPullBatch) private {
    if (params.prevPullBatch != newPullBatch) {
      if (params.prevPullBatch != 0) {
        _removeFromPullable(params.insured, params.prevPullBatch);
      }
      if (newPullBatch != 0) {
        _addToPullable(params.insured, newPullBatch);
      }
    }
  }

  /// @dev Finds which batch to add coverage demand to.
  /// @param nextBatchNo Attempts to use if it is accepting coverage demand
  /// @return b Returns the current batch, its number and whether batches were filled
  /// @return thisBatchNo
  /// @return isFirstOfOpen
  function _findBatchToAppend(uint64 nextBatchNo)
    private
    returns (
      Rounds.Batch memory b,
      uint64 thisBatchNo,
      bool isFirstOfOpen
    )
  {
    uint64 firstOpen = _firstOpenBatchNo;
    if (firstOpen == 0) {
      // there are no batches
      Sanity.require(_batchCount == 0);
      Sanity.require(nextBatchNo == 0);
      _initTimeMark(_latestBatchNo = _batchCount = _partial.batchNo = _firstOpenBatchNo = 1);
      return (b, 1, true);
    }

    if (nextBatchNo != 0 && (b = _batches[nextBatchNo]).isOpen()) {
      thisBatchNo = nextBatchNo;
    } else {
      b = _batches[thisBatchNo = firstOpen];
    }

    if (b.nextBatchNo == 0) {
      Sanity.require(b.rounds == 0);
    } else {
      PartialState memory part = _partial;
      if (part.batchNo == thisBatchNo) {
        uint24 remainingRounds = part.roundCoverage == 0 ? part.roundNo : part.roundNo + 1;
        if (remainingRounds > 0) {
          _splitBatch(remainingRounds, b);

          if (part.roundCoverage == 0) {
            b.state = Rounds.State.Full;

            Rounds.CoveragePremium memory premium = _poolPremium;
            _addPartialToTotalPremium(thisBatchNo, premium, b);
            _poolPremium = premium;

            _partial = PartialState({roundCoverage: 0, batchNo: b.nextBatchNo, roundNo: 0});
          }
          _batches[thisBatchNo] = b;
          if (firstOpen == thisBatchNo) {
            _firstOpenBatchNo = firstOpen = b.nextBatchNo;
          }
          b = _batches[thisBatchNo = b.nextBatchNo];
        }
      }
    }

    return (b, thisBatchNo, thisBatchNo == firstOpen);
  }

  function _adjustedTotalUnits(uint80 units) private view returns (uint80 n) {
    n = _pendingCancelledCoverageUnits;
    if (n >= units) {
      return 0;
    }
    unchecked {
      return units - n;
    }
  }

  /// @dev adds the demand to the list of demands
  function _addToSlot(
    Rounds.Demand memory demand,
    Rounds.Demand[] storage demands,
    uint16 addPerRound,
    uint24 batchRounds,
    uint40 premiumRate
  ) private returns (bool) {
    if (demand.unitPerRound == addPerRound && demand.premiumRate == premiumRate) {
      uint24 t;
      unchecked {
        t = batchRounds + demand.rounds;
      }
      if (t >= batchRounds) {
        demand.rounds = t;
        return false;
      }
      // overflow on amount of rounds per slot
    }

    if (demand.unitPerRound != 0) {
      demands.push(demand);
    }
    return true;
  }

  /// @dev Adds units to the batch. Can split the batch when the number of units is less than the number of rounds inside the batch.
  /// The unitCount units are evenly distributed across rounds by increase the # of units per round
  function _addToBatch(
    uint64 unitCount,
    Rounds.Batch memory b,
    Rounds.InsuredEntry memory entry,
    AddCoverageDemandParams memory params,
    bool canClose
  ) private returns (uint16 addPerRound, bool takeNext) {
    Sanity.require(b.isOpen() && b.rounds > 0);

    if (unitCount < b.rounds) {
      // split the batch or return the non-allocated units
      uint24 splitRounds = internalBatchSplit(entry.demandedUnits, entry.params.minUnits(), b.rounds, uint24(unitCount));
      // console.log('addToBatch-internalBatchSplit', splitRounds);
      if (splitRounds == 0) {
        return (0, false);
      }
      Sanity.require(unitCount >= splitRounds);
      // console.log('batchSplit-before', splitRounds, b.rounds, b.nextBatchNo);
      _splitBatch(splitRounds, b);
      // console.log('batchSplit-after', b.rounds, b.nextBatchNo);
    }

    (uint16 maxShareUnitsPerRound, uint16 minUnitsPerRound, uint16 readyUnitsPerRound, uint16 maxUnitsPerRound) = internalRoundLimits(
      _adjustedTotalUnits(b.totalUnitsBeforeBatch),
      b.rounds,
      b.unitPerRound,
      entry.demandedUnits,
      entry.params.maxShare()
    );

    // console.log('addToBatch-checkLimits', b.unitPerRound, b.rounds);
    // console.log('addToBatch-limits', maxShareUnitsPerRound, minUnitsPerRound, maxUnitsPerRound);

    if (maxShareUnitsPerRound > 0) {
      takeNext = true;
      if (b.unitPerRound < maxUnitsPerRound) {
        addPerRound = maxUnitsPerRound - b.unitPerRound;
        if (addPerRound > maxShareUnitsPerRound) {
          addPerRound = maxShareUnitsPerRound;
        }
        uint64 n = unitCount / b.rounds;
        if (addPerRound > n) {
          addPerRound = uint16(n);
        }
        Sanity.require(addPerRound > 0);

        b.unitPerRound += addPerRound;
        b.roundPremiumRateSum += uint56(params.premiumRate) * addPerRound;
      }
    }

    if (b.unitPerRound >= minUnitsPerRound) {
      b.state = canClose && b.unitPerRound >= readyUnitsPerRound ? Rounds.State.Ready : Rounds.State.ReadyMin;
    }
  }

  function internalRoundLimits(
    uint80 totalUnitsBeforeBatch,
    uint24 batchRounds,
    uint16 unitPerRound,
    uint64 demandedUnits,
    uint16 maxShare
  )
    internal
    virtual
    returns (
      uint16 maxAddUnitsPerRound,
      uint16 minUnitsPerRound,
      uint16 readyUnitsPerRound,
      uint16 maxUnitsPerRound
    );

  function internalBatchSplit(
    uint64 demandedUnits,
    uint64 minUnits,
    uint24 batchRounds,
    uint24 remainingUnits
  ) internal virtual returns (uint24 splitRounds);

  function internalBatchAppend(
    uint80 totalUnitsBeforeBatch,
    uint32 openRounds,
    uint64 unitCount
  ) internal virtual returns (uint24 rounds);

  /// @dev Reduces the current batch's rounds and adds the leftover rounds to a new batch.
  /// @dev Checks if this is the new latest batch
  /// @param remainingRounds Number of rounds to reduce the current batch to
  /// @param b The batch to add leftover rounds to
  function _splitBatch(uint24 remainingRounds, Rounds.Batch memory b) private {
    if (b.rounds == remainingRounds) return;
    Sanity.require(b.rounds > remainingRounds);

    uint64 newBatchNo = ++_batchCount;

    _batches[newBatchNo] = Rounds.Batch({
      nextBatchNo: b.nextBatchNo,
      totalUnitsBeforeBatch: b.totalUnitsBeforeBatch + uint80(remainingRounds) * b.unitPerRound,
      rounds: b.rounds - remainingRounds,
      unitPerRound: b.unitPerRound,
      state: b.state,
      roundPremiumRateSum: b.roundPremiumRateSum
    });
    _initTimeMark(newBatchNo);

    b.rounds = remainingRounds;
    if (b.nextBatchNo == 0) {
      _latestBatchNo = newBatchNo;
    }
    b.nextBatchNo = newBatchNo;
  }

  function _splitBatch(uint24 remainingRounds, uint64 batchNo) private returns (uint64) {
    Rounds.Batch memory b = _batches[batchNo];
    _splitBatch(remainingRounds, b);
    _batches[batchNo] = b;
    return b.nextBatchNo;
  }

  struct GetCoveredDemandParams {
    uint256 loopLimit;
    uint256 receivedCoverage;
    uint256 receivedPremium;
    address insured;
    bool done;
  }

  /// @dev Get the amount of demand that has been covered and the premium earned from it
  /// @param params Updates the received coverage
  /// @return coverage The values in this struct ONLY reflect the insured. IS FINALIZED
  /// @return covered Updated information based on newly collected coverage
  /// @return premium The premium paid and new premium rate
  function internalGetCoveredDemand(GetCoveredDemandParams memory params)
    internal
    view
    returns (
      DemandedCoverage memory coverage,
      Rounds.Coverage memory covered,
      Rounds.CoveragePremium memory premium
    )
  {
    Rounds.Demand[] storage demands = _demands[params.insured];
    premium = _premiums[params.insured];

    (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = (
      premium.coveragePremium,
      premium.coveragePremiumRate,
      premium.lastUpdatedAt
    );
    params.receivedPremium = uint256(_unitSize).wadMul(coverage.totalPremium);

    uint256 demandLength = demands.length;
    if (demandLength == 0) {
      params.done = true;
    } else {
      covered = _covered[params.insured];
      params.receivedCoverage = covered.coveredUnits;

      for (; params.loopLimit > 0; params.loopLimit--) {
        if (covered.lastUpdateIndex >= demandLength || !_collectCoveredDemandSlot(demands[covered.lastUpdateIndex], coverage, covered, premium)) {
          params.done = true;
          break;
        }
      }
    }

    _finalizePremium(coverage, true);
    coverage.totalDemand = uint256(_unitSize) * _insureds[params.insured].demandedUnits;
    coverage.totalCovered += uint256(_unitSize) * covered.coveredUnits;
    params.receivedCoverage = uint256(_unitSize) * (covered.coveredUnits - params.receivedCoverage);
    params.receivedPremium = coverage.totalPremium - params.receivedPremium;
  }

  function internalUpdateCoveredDemand(GetCoveredDemandParams memory params) internal returns (DemandedCoverage memory coverage) {
    (coverage, _covered[params.insured], _premiums[params.insured]) = internalGetCoveredDemand(params);
  }

  /// @dev Sets the function parameters to their correct values by calculating on new full batches
  /// @param d Update startBatchNo is set to the first open batch and rounds from last updated
  /// @param covered Update covered units and last known info based on the newly counted full batches
  /// @param premium Update total premium collected and the new premium rate for full batches
  /// @param coverage Update total premium collected and the new premium rate including the partial batch
  /// @return true if the demand has been completely filled
  function _collectCoveredDemandSlot(
    Rounds.Demand memory d,
    DemandedCoverage memory coverage,
    Rounds.Coverage memory covered,
    Rounds.CoveragePremium memory premium
  ) private view returns (bool) {
    // console.log('collect', d.rounds, covered.lastUpdateBatchNo, covered.lastUpdateRounds);

    uint24 fullRounds;
    if (covered.lastUpdateRounds > 0) {
      d.rounds -= covered.lastUpdateRounds; //Reduce by # of full rounds that was kept track of until lastUpdateBatchNo
      d.startBatchNo = covered.lastUpdateBatchNo;
    }
    if (covered.lastPartialRoundNo > 0) {
      covered.coveredUnits -= uint64(covered.lastPartialRoundNo) * d.unitPerRound;
      covered.lastPartialRoundNo = 0;
    }

    Rounds.Batch memory b;
    while (d.rounds > fullRounds) {
      Sanity.require(d.startBatchNo != 0);
      b = _batches[d.startBatchNo];
      // console.log('collectBatch', d.startBatchNo, b.nextBatchNo, b.rounds);

      if (!b.isFull()) break;
      // console.log('collectBatch1');

      // zero rounds may be present due to cancellations
      if (b.rounds > 0) {
        fullRounds += b.rounds;

        (premium.coveragePremium, premium.coveragePremiumRate, premium.lastUpdatedAt) = _calcPremium(
          d,
          premium,
          b.rounds,
          0,
          d.premiumRate,
          b.unitPerRound
        );
      }
      d.startBatchNo = b.nextBatchNo;
    }

    covered.coveredUnits += uint64(fullRounds) * d.unitPerRound;
    (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = (
      premium.coveragePremium,
      premium.coveragePremiumRate,
      premium.lastUpdatedAt
    );

    // if the covered.lastUpdateIndex demand has been fully covered
    if (d.rounds == fullRounds) {
      covered.lastUpdateRounds = 0;
      covered.lastUpdateBatchNo = 0;
      covered.lastUpdateIndex++;
      return true;
    }

    Sanity.require(d.rounds > fullRounds);
    Sanity.require(d.startBatchNo != 0);
    covered.lastUpdateRounds += fullRounds;
    covered.lastUpdateBatchNo = d.startBatchNo;

    PartialState memory part = _partial;
    // console.log('collectCheck', part.batchNo, covered.lastUpdateBatchNo);
    if (part.batchNo == d.startBatchNo) {
      // console.log('collectPartial', part.roundNo, part.roundCoverage);
      if (part.roundNo > 0 || part.roundCoverage > 0) {
        covered.coveredUnits += uint64(covered.lastPartialRoundNo = part.roundNo) * d.unitPerRound;
        coverage.pendingCovered = (uint256(part.roundCoverage) * d.unitPerRound) / _batches[d.startBatchNo].unitPerRound;

        (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = _calcPremium(
          d,
          premium,
          part.roundNo,
          coverage.pendingCovered,
          d.premiumRate,
          b.unitPerRound
        );
      }
    }

    return false;
  }

  /// @dev Calculate the actual premium values since variables keep track of number of coverage units instead of
  /// amount of coverage currency (coverage units * unit size).
  /// @dev NOTE: The effects from this should not be used in any calculations for modifying state
  function _finalizePremium(DemandedCoverage memory coverage, bool roundUp) private view {
    coverage.premiumRate = roundUp ? uint256(_unitSize).wadMulUp(coverage.premiumRate) : uint256(_unitSize).wadMul(coverage.premiumRate);
    coverage.totalPremium = uint256(_unitSize).wadMul(coverage.totalPremium);
    if (coverage.premiumUpdatedAt != 0) {
      coverage.totalPremium += coverage.premiumRate * (block.timestamp - coverage.premiumUpdatedAt);
      coverage.premiumRateUpdatedAt = coverage.premiumUpdatedAt;
      coverage.premiumUpdatedAt = uint32(block.timestamp);
    }
  }

  /// @dev Calculate the new premium values by including the rounds that have been filled for demand d and
  /// the partial rounds
  function _calcPremium(
    Rounds.Demand memory d,
    Rounds.CoveragePremium memory premium,
    uint24 rounds,
    uint256 pendingCovered,
    uint256 premiumRate,
    uint256 batchUnitPerRound
  )
    private
    view
    returns (
      uint96 coveragePremium,
      uint64 coveragePremiumRate,
      uint32 lastUpdatedAt
    )
  {
    TimeMark memory mark = _marks[d.startBatchNo];
    // console.log('premiumBefore', d.startBatchNo, d.unitPerRound, rounds);
    // console.log('premiumBefore', mark.timestamp, premium.lastUpdatedAt, mark.duration);
    // console.log('premiumBefore', premium.coveragePremium, premium.coveragePremiumRate, pendingCovered);
    // console.log('premiumBefore', mark.coverageTW, premiumRate, batchUnitPerRound);
    uint256 v = premium.coveragePremium;
    if (premium.lastUpdatedAt != 0) {
      v += uint256(premium.coveragePremiumRate) * (mark.timestamp - premium.lastUpdatedAt);
    }
    lastUpdatedAt = mark.timestamp;

    if (mark.coverageTW > 0) {
      // normalization by unitSize to reduce storage requirements
      v += _calcTimeMarkPortion(premiumRate * mark.coverageTW, d.unitPerRound, uint256(_unitSize) * batchUnitPerRound);
    }
    coveragePremium = v.asUint96();

    v = premium.coveragePremiumRate + premiumRate * uint256(rounds) * d.unitPerRound;
    if (pendingCovered > 0) {
      // normalization by unitSize to reduce storage requirements
      // roundup is aggresive here to ensure that this pools is guaranteed to pay not less that it pays out
      v += (pendingCovered * premiumRate + (_unitSize - 1)) / _unitSize;
    }
    Arithmetic.require((coveragePremiumRate = uint64(v)) == v);
    // console.log('premiumAfter', coveragePremium, coveragePremiumRate);
  }

  function _calcTimeMarkPortion(
    uint256 tw,
    uint16 unitPerRound,
    uint256 batchRoundUnits
  ) private pure returns (uint256) {
    return (tw * unitPerRound + (batchRoundUnits - 1)) / batchRoundUnits;
  }

  /// @dev Update the premium totals of coverage by including batch b
  function _collectPremiumTotalsFromPartial(
    PartialState memory part,
    Rounds.Batch memory b,
    Rounds.CoveragePremium memory premium,
    DemandedCoverage memory coverage
  ) private view {
    if (b.isFull() || (part.roundNo == 0 && part.roundCoverage == 0)) {
      (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = (
        premium.coveragePremium,
        premium.coveragePremiumRate,
        premium.lastUpdatedAt
      );
      return;
    }

    Rounds.Demand memory d;
    d.startBatchNo = part.batchNo;
    d.unitPerRound = 1;

    (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = _calcPremium(
      d,
      premium,
      part.roundNo,
      (part.roundCoverage + (b.unitPerRound - 1)) / b.unitPerRound,
      b.roundPremiumRateSum,
      b.unitPerRound
    );
  }

  function internalGetCoveredTotals() internal view returns (uint256 totalCovered, uint256 pendingCovered) {
    uint64 batchNo = _partial.batchNo;
    if (batchNo > 0) {
      Rounds.Batch storage b = _batches[batchNo];
      totalCovered = _unitSize * (_adjustedTotalUnits(b.totalUnitsBeforeBatch) + uint256(_partial.roundNo) * b.unitPerRound);
      pendingCovered = _partial.roundCoverage;
    }
  }

  function internalGetPremiumTotals() internal view returns (DemandedCoverage memory coverage) {
    return internalGetPremiumTotals(_partial, _poolPremium);
  }

  /// @return coverage All the coverage and premium values
  /// @dev IS FINALIZED
  function internalGetPremiumTotals(PartialState memory part, Rounds.CoveragePremium memory premium)
    internal
    view
    returns (DemandedCoverage memory coverage)
  {
    if (part.batchNo == 0) {
      return coverage;
    }

    Rounds.Batch memory b = _batches[part.batchNo];
    _collectPremiumTotalsFromPartial(part, b, premium, coverage);

    coverage.totalCovered = _adjustedTotalUnits(b.totalUnitsBeforeBatch) + uint256(part.roundNo) * b.unitPerRound;
    coverage.pendingCovered = part.roundCoverage;

    _finalizePremium(coverage, false);
    coverage.totalCovered *= _unitSize;
  }

  /// @dev Get the Pool's total amount of coverage that has been demanded, covered and allocated (partial round) and
  /// the corresponding premium based on these values
  /// @dev IS FINALIZED
  function internalGetTotals(uint256 loopLimit) internal view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    PartialState memory part = _partial;
    if (part.batchNo == 0) return (coverage, total);

    uint64 thisBatch = part.batchNo;

    Rounds.Batch memory b = _batches[thisBatch];
    // console.log('batch0', thisBatch, b.nextBatchNo, b.rounds);
    // console.log('batch1', part.roundNo);
    _collectPremiumTotalsFromPartial(part, b, _poolPremium, coverage);

    uint80 adjustedTotal = _adjustedTotalUnits(b.totalUnitsBeforeBatch);
    coverage.totalCovered = adjustedTotal + uint256(part.roundNo) * b.unitPerRound;
    coverage.totalDemand = adjustedTotal + uint256(b.rounds) * b.unitPerRound;
    coverage.pendingCovered = part.roundCoverage;
    total.batchCount = 1;

    if (b.isReady()) {
      total.usableRounds = b.rounds - part.roundNo;
      total.totalCoverable = uint256(total.usableRounds) * b.unitPerRound;
    }
    if (b.isOpen()) {
      total.openRounds += b.rounds - part.roundNo;
    }

    for (; loopLimit > 0 && b.nextBatchNo != 0; loopLimit--) {
      thisBatch = b.nextBatchNo;
      b = _batches[b.nextBatchNo];
      // console.log('batch', thisBatch, b.nextBatchNo);

      total.batchCount++;
      coverage.totalDemand += uint256(b.rounds) * b.unitPerRound;

      if (b.isReady()) {
        total.usableRounds += b.rounds;
        total.totalCoverable += uint256(b.rounds) * b.unitPerRound;
      }

      if (b.isOpen()) {
        total.openRounds += b.rounds;
      }
    }

    _finalizePremium(coverage, false);
    coverage.totalCovered *= _unitSize;
    coverage.totalDemand *= _unitSize;
    total.totalCoverable = total.totalCoverable * _unitSize - coverage.pendingCovered;
  }

  struct AddCoverageParams {
    Rounds.CoveragePremium premium;
    /// @dev != 0 also indicates that at least one round was added
    uint64 openBatchNo;
    bool openBatchUpdated;
    bool batchUpdated;
    bool premiumUpdated;
    // uint256 unitsCovered;
  }

  /// @dev Satisfy coverage demand by adding coverage
  function internalAddCoverage(uint256 amount, uint256 loopLimit)
    internal
    returns (
      uint256 remainingAmount,
      uint256, /* remainingLoopLimit */
      AddCoverageParams memory params,
      PartialState memory part
    )
  {
    part = _partial;

    if (amount == 0 || loopLimit == 0 || part.batchNo == 0) {
      return (amount, loopLimit, params, part);
    }

    Rounds.Batch memory b;
    params.premium = _poolPremium;

    (remainingAmount, loopLimit, b) = _addCoverage(amount, loopLimit, part, params);
    if (params.batchUpdated) {
      _batches[part.batchNo] = b;
    }
    if (params.premiumUpdated) {
      _poolPremium = params.premium;
    }
    if (params.openBatchUpdated) {
      Sanity.require(params.openBatchNo != 0);
      _firstOpenBatchNo = params.openBatchNo;
    }
    _partial = part;
    // console.log('partial3', part.batchNo, part.roundNo, part.roundCoverage);

    return (remainingAmount, loopLimit, params, part);
  }

  /// @dev Adds coverage to the pool and stops if there are no batches left to add coverage to or
  /// if the current batch is not ready to accept coverage
  function _addCoverage(
    uint256 amount,
    uint256 loopLimit,
    PartialState memory part,
    AddCoverageParams memory params
  )
    internal
    returns (
      uint256, /* remainingAmount */
      uint256 remainingLoopLimit,
      Rounds.Batch memory b
    )
  {
    b = _batches[part.batchNo];

    if (part.roundCoverage > 0) {
      Sanity.require(b.isReady());

      _updateTimeMark(part, b.unitPerRound);

      uint256 maxRoundCoverage = uint256(_unitSize) * b.unitPerRound;
      uint256 vacant = maxRoundCoverage - part.roundCoverage;
      if (amount < vacant) {
        part.roundCoverage += uint128(amount);
        return (0, loopLimit - 1, b);
      }
      // params.unitsCovered = b.unitPerRound;
      part.roundCoverage = 0;
      part.roundNo++;
      amount -= vacant;
    } else if (!b.isReady()) {
      return (amount, loopLimit - 1, b);
    }

    /// @dev != 0 also indicates that at least one round was added
    params.openBatchNo = _firstOpenBatchNo;
    while (true) {
      loopLimit--;

      // if filled in the final round of a batch
      if (part.roundNo >= b.rounds) {
        Sanity.require(part.roundNo == b.rounds);
        Sanity.require(part.roundCoverage == 0);

        if (b.state != Rounds.State.Full) {
          b.state = Rounds.State.Full;
          params.batchUpdated = true;

          if (b.unitPerRound == 0) {
            // this is a special case when all units were removed by cancellations
            Sanity.require(b.rounds == 0);
            // total premium doesn't need to be updated as the rate remains the same
          } else {
            _addPartialToTotalPremium(part.batchNo, params.premium, b);
            params.premiumUpdated = true;
          }
        }

        if (params.batchUpdated) {
          _batches[part.batchNo] = b;
          params.batchUpdated = false;
        }

        if (part.batchNo == params.openBatchNo) {
          params.openBatchNo = b.nextBatchNo;
          params.openBatchUpdated = true;
        }

        if (b.nextBatchNo == 0) break;

        // do NOT do like this here:  part = PartialState({batchNo: b.nextBatchNo, roundNo: 0, roundCoverage: 0});
        (part.batchNo, part.roundNo, part.roundCoverage) = (b.nextBatchNo, 0, 0);
        // console.log('partial0', part.batchNo, part.roundNo, part.roundCoverage);

        uint80 totalUnitsBeforeBatch = b.totalUnitsBeforeBatch;
        if (b.rounds > 0) {
          _openRounds -= b.rounds;
          totalUnitsBeforeBatch += uint80(b.rounds) * b.unitPerRound;
        }

        b = _batches[part.batchNo];

        if (totalUnitsBeforeBatch != b.totalUnitsBeforeBatch) {
          b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
          params.batchUpdated = true;
        }

        if (amount == 0) break;
        if (!b.isReady()) {
          return (amount, loopLimit, b);
        }
      } else {
        _updateTimeMark(part, b.unitPerRound);

        uint256 maxRoundCoverage = uint256(_unitSize) * b.unitPerRound;
        uint256 n = amount / maxRoundCoverage;

        uint24 vacantRounds = b.rounds - part.roundNo;
        Sanity.require(vacantRounds > 0);

        if (n < vacantRounds) {
          // params.unitsCovered += n * b.unitPerRound;
          part.roundNo += uint24(n);
          part.roundCoverage = uint128(amount - maxRoundCoverage * n);
          amount = 0;
          break;
        }

        // params.unitsCovered += vacantRounds * b.unitPerRound;
        part.roundNo = b.rounds;
        amount -= maxRoundCoverage * vacantRounds;
        if (loopLimit > 0) continue; // make sure to move to the next batch
      }
      if (amount == 0 || loopLimit == 0) {
        break;
      }
    }

    return (amount, loopLimit, b);
  }

  /// @dev Sets the values of premium to include the partial batch b
  function _addPartialToTotalPremium(
    uint64 batchNo,
    Rounds.CoveragePremium memory premium,
    Rounds.Batch memory b
  ) internal view {
    (premium.coveragePremium, premium.coveragePremiumRate, premium.lastUpdatedAt) = _calcPremium(
      Rounds.Demand(batchNo, 0, 0, 1),
      premium,
      b.rounds,
      0,
      b.roundPremiumRateSum,
      b.unitPerRound
    );
  }

  function _initTimeMark(uint64 batchNo) private {
    // NB! this moves some of gas costs from addCoverage to addCoverageDemand
    _marks[batchNo].timestamp = 1;
  }

  /// @dev Updates the timeMark for the partial batch which calculates the "area under the curve"
  /// of the coverage curve over time
  function _updateTimeMark(PartialState memory part, uint256 batchUnitPerRound) private {
    // console.log('==updateTimeMark', part.batchNo);
    Sanity.require(part.batchNo != 0);
    TimeMark memory mark = _marks[part.batchNo];

    if (mark.timestamp <= 1) {
      mark.coverageTW = 0;
      mark.duration = 0;
    } else {
      uint32 duration = uint32(block.timestamp - mark.timestamp);
      if (duration == 0) return;

      uint256 coverageTW = mark.coverageTW + (uint256(_unitSize) * part.roundNo * batchUnitPerRound + part.roundCoverage) * duration;
      Value.require(coverageTW == (mark.coverageTW = uint192(coverageTW)));

      mark.duration += duration;
    }
    mark.timestamp = uint32(block.timestamp);

    _marks[part.batchNo] = mark;
  }

  struct Dump {
    uint64 batchCount;
    uint64 latestBatch;
    /// @dev points to an earliest round that is open, can be zero when all rounds are full
    uint64 firstOpenBatch;
    PartialState part;
    Rounds.Batch[] batches;
  }

  /// @dev Return coverage and premium information for an insured
  function _dumpInsured(address insured)
    internal
    view
    returns (
      Rounds.InsuredEntry memory,
      Rounds.Demand[] memory,
      Rounds.Coverage memory,
      Rounds.CoveragePremium memory
    )
  {
    return (_insureds[insured], _demands[insured], _covered[insured], _premiums[insured]);
  }

  /// @return dump The current state of the batches of the system
  function _dump() internal view returns (Dump memory dump) {
    dump.batchCount = _batchCount;
    dump.latestBatch = _latestBatchNo;
    dump.firstOpenBatch = _firstOpenBatchNo;
    dump.part = _partial;
    uint64 j = 0;
    for (uint64 i = dump.part.batchNo; i > 0; i = _batches[i].nextBatchNo) {
      j++;
    }
    dump.batches = new Rounds.Batch[](j);
    j = 0;
    for (uint64 i = dump.part.batchNo; i > 0; ) {
      Rounds.Batch memory b = _batches[i];
      i = b.nextBatchNo;
      dump.batches[j++] = b;
    }
  }

  /// @return If coverage can be added to the partial state
  function internalCanAddCoverage() internal view returns (bool) {
    uint64 batchNo = _partial.batchNo;
    return batchNo != 0 && (_partial.roundCoverage > 0 || _batches[batchNo].state.isReady());
  }

  struct CancelCoverageDemandParams {
    uint256 loopLimit;
    address insured;
    bool done;
    // temp var
    uint80 totalUnitsBeforeBatch;
    // result
    uint256[] rateBands;
  }

  /// @dev Try to cancel `unitCount` units of coverage demand
  /// @return The amount of units that were cancelled
  function internalCancelCoverageDemand(uint64 unitCount, CancelCoverageDemandParams memory params) internal returns (uint64) {
    Rounds.InsuredEntry storage entry = _insureds[params.insured];
    Access.require(entry.status == MemberStatus.Accepted);

    _removeFromPullable(params.insured, entry.nextBatchNo);

    if (unitCount == 0 || params.loopLimit == 0 || entry.demandedUnits == _covered[params.insured].coveredUnits) {
      return 0;
    }

    Rounds.Demand[] storage demands = _demands[params.insured];

    (uint256 index, uint64 batchNo, uint256 skippedRounds, Rounds.Demand memory demand, uint64 cancelledUnits) = _findAndAdjustUncovered(
      unitCount,
      demands,
      params
    );

    if (cancelledUnits == 0) {
      return 0;
    }

    entry.nextBatchNo = batchNo;
    entry.demandedUnits -= cancelledUnits;

    uint24 cancelFirstSlotRounds = uint24(demand.rounds - skippedRounds);
    Sanity.require(cancelFirstSlotRounds > 0);

    demand.rounds = uint24(skippedRounds);

    (batchNo, params.totalUnitsBeforeBatch) = _adjustUncoveredBatches(
      batchNo,
      cancelFirstSlotRounds,
      _batches[batchNo].totalUnitsBeforeBatch,
      demand
    );

    _adjustUncoveredSlots(batchNo, uint80(cancelFirstSlotRounds) * demand.unitPerRound, demands, index + 1, params);

    uint256 bandCount = 0;
    for (uint256 i = demands.length - 1; i > index; i--) {
      bandCount = _addToRateBand(params, bandCount, demands[i]);
      demands.pop();
    }

    if (demand.rounds == 0) {
      bandCount = _addToRateBand(params, bandCount, demands[index]);
      demands.pop();
    } else {
      bandCount = _addToRateBand(params, bandCount, demand.premiumRate, uint64(demands[index].rounds - demand.rounds) * demand.unitPerRound);
      demands[index] = demand;
    }
    Sanity.require(bandCount == params.rateBands.length);

    return cancelledUnits;
  }

  function _addToRateBand(
    CancelCoverageDemandParams memory params,
    uint256 bandCount,
    Rounds.Demand storage d
  ) private view returns (uint256) {
    return _addToRateBand(params, bandCount, d.premiumRate, uint64(d.unitPerRound) * d.rounds);
  }

  function _addToRateBand(
    CancelCoverageDemandParams memory params,
    uint256 bandCount,
    uint40 rate,
    uint64 units
  ) private pure returns (uint256) {
    if (bandCount > 0) {
      uint256 bandRate = params.rateBands[bandCount - 1] >> (256 - Rounds.DEMAND_RATE_BITS);
      if (bandRate == rate) {
        params.rateBands[bandCount - 1] += units;
        return bandCount;
      }
    }

    params.rateBands[bandCount] = (uint256(rate) << (256 - Rounds.DEMAND_RATE_BITS)) + units;
    return bandCount + 1;
  }

  /// @dev Remove coverage demand from batches
  function _findAndAdjustUncovered(
    uint64 unitCount,
    Rounds.Demand[] storage demands,
    CancelCoverageDemandParams memory params
  )
    private
    returns (
      uint256 index,
      uint64 batchNo,
      uint256 skippedRounds,
      Rounds.Demand memory demand,
      uint64 cancelledUnits
    )
  {
    PartialState memory part = _partial;
    uint256 rateBands;

    for (index = demands.length; index > 0 && params.loopLimit > 0; params.loopLimit--) {
      index--;

      Rounds.Demand memory prev = demand;
      demand = demands[index];
      if (prev.premiumRate != demand.premiumRate) {
        rateBands++;
      }

      uint64 cancelUnits;
      (params.done, batchNo, cancelUnits, skippedRounds) = _findUncoveredBatch(part, demand, unitCount - cancelledUnits);

      cancelledUnits += cancelUnits;
      if (params.done) {
        if (skippedRounds == demand.rounds) {
          // the whole demand slot was skipped, so use the previous one
          Sanity.require(cancelUnits == 0);
          index++;
          demand = prev;
          batchNo = prev.startBatchNo;
          skippedRounds = 0;
        }
        break;
      }

      Sanity.require(skippedRounds == 0);
    }

    params.rateBands = new uint256[](rateBands);
  }

  /// @dev Find the batch to remove coverage demand from
  function _findUncoveredBatch(
    PartialState memory part,
    Rounds.Demand memory demand,
    uint256 unitCount
  )
    private
    returns (
      bool done,
      uint64 batchNo,
      uint64 cancelUnits,
      uint256 skippedRounds
    )
  {
    batchNo = demand.startBatchNo;

    uint256 partialRounds;
    if (batchNo == part.batchNo) {
      done = true;
    } else if (_batches[batchNo].state.isFull()) {
      for (;;) {
        Rounds.Batch storage batch = _batches[batchNo];
        skippedRounds += batch.rounds;
        if (skippedRounds >= demand.rounds) {
          Sanity.require(skippedRounds == demand.rounds);
          return (true, batchNo, 0, skippedRounds);
        }
        batchNo = batch.nextBatchNo;
        if (batchNo == part.batchNo) {
          break;
        }
      }
      done = true;
    }
    if (done) {
      partialRounds = part.roundCoverage == 0 ? part.roundNo : part.roundNo + 1;
    }

    uint256 neededRounds = (uint256(unitCount) + demand.unitPerRound - 1) / demand.unitPerRound;

    if (demand.rounds <= skippedRounds + partialRounds + neededRounds) {
      // we should cancel all demands of this slot
      if (partialRounds > 0) {
        // the partial batch can alway be split
        batchNo = _splitBatch(uint24(partialRounds), batchNo);
        skippedRounds += partialRounds;
      }
      neededRounds = demand.rounds - skippedRounds;
    } else {
      // there is more demand in this slot than needs to be cancelled
      // so some batches may be skipped
      done = true;
      uint256 excessRounds = uint256(demand.rounds) - skippedRounds - neededRounds;

      for (; excessRounds > 0; ) {
        Rounds.Batch storage batch = _batches[batchNo];

        uint24 rounds = batch.rounds;
        if (rounds > excessRounds) {
          uint24 remainingRounds;
          unchecked {
            remainingRounds = rounds - uint24(excessRounds);
          }
          if (batchNo == part.batchNo || internalCanSplitBatchOnCancel(batchNo, remainingRounds)) {
            // partial batch can always be split, otherwise the policy decides
            batchNo = _splitBatch(remainingRounds, batchNo);
          } else {
            // cancel more than actually requested to avoid fragmentation of batches
            neededRounds += remainingRounds;
          }
          break;
        } else {
          skippedRounds += rounds;
          excessRounds -= rounds;
          batchNo = batch.nextBatchNo;
        }
      }
    }
    cancelUnits = uint64(neededRounds * demand.unitPerRound);
  }

  function internalCanSplitBatchOnCancel(uint64 batchNo, uint24 remainingRounds) internal view virtual returns (bool) {}

  function _adjustUncoveredSlots(
    uint64 batchNo,
    uint80 totalUnitsAdjustment,
    Rounds.Demand[] storage demands,
    uint256 startFrom,
    CancelCoverageDemandParams memory params
  ) private {
    uint256 maxIndex = demands.length;

    for (uint256 i = startFrom; i < maxIndex; i++) {
      Rounds.Demand memory d = demands[i];
      if (d.startBatchNo != batchNo) {
        params.totalUnitsBeforeBatch = _batches[d.startBatchNo].totalUnitsBeforeBatch;
        if (params.totalUnitsBeforeBatch > totalUnitsAdjustment) {
          params.totalUnitsBeforeBatch -= totalUnitsAdjustment;
        } else {
          params.totalUnitsBeforeBatch = 0;
        }
      }
      (batchNo, params.totalUnitsBeforeBatch) = _adjustUncoveredBatches(d.startBatchNo, d.rounds, params.totalUnitsBeforeBatch, d);
      totalUnitsAdjustment += uint80(d.rounds) * d.unitPerRound;
    }

    if (totalUnitsAdjustment > 0) {
      _pendingCancelledDemandUnits += totalUnitsAdjustment;
    }
  }

  function _adjustUncoveredBatches(
    uint64 batchNo,
    uint256 rounds,
    uint80 totalUnitsBeforeBatch,
    Rounds.Demand memory demand
  ) private returns (uint64, uint80) {
    for (; rounds > 0; ) {
      Rounds.Batch storage batch = _batches[batchNo];
      (uint24 br, uint16 bupr) = (batch.rounds, batch.unitPerRound);
      rounds -= br;
      if (bupr == demand.unitPerRound) {
        (batch.rounds, batch.roundPremiumRateSum, bupr) = (0, 0, 0);
        _openRounds -= br;
      } else {
        bupr -= demand.unitPerRound;
        batch.roundPremiumRateSum -= uint56(demand.unitPerRound) * demand.premiumRate;
      }

      batch.unitPerRound = bupr;
      batch.totalUnitsBeforeBatch = totalUnitsBeforeBatch;

      totalUnitsBeforeBatch += uint80(br) * bupr;

      if (batch.state == Rounds.State.Ready) {
        batch.state = Rounds.State.ReadyMin;
      }

      batchNo = batch.nextBatchNo;
    }
    return (batchNo, totalUnitsBeforeBatch);
  }

  function internalGetUnadjustedUnits()
    internal
    view
    returns (
      uint256 total,
      uint256 pendingCovered,
      uint256 pendingDemand
    )
  {
    Rounds.Batch storage b = _batches[_partial.batchNo];
    return (uint256(b.totalUnitsBeforeBatch) + _partial.roundNo * b.unitPerRound, _pendingCancelledCoverageUnits, _pendingCancelledDemandUnits);
  }

  function internalApplyAdjustmentsToTotals() internal {
    uint80 totals = _pendingCancelledCoverageUnits;
    if (totals == 0 && _pendingCancelledDemandUnits == 0) {
      return;
    }
    (_pendingCancelledCoverageUnits, _pendingCancelledDemandUnits) = (0, 0);

    uint64 batchNo = _partial.batchNo;
    totals = _batches[batchNo].totalUnitsBeforeBatch - totals;

    for (; batchNo > 0; ) {
      Rounds.Batch storage b = _batches[batchNo];
      b.totalUnitsBeforeBatch = totals;
      totals += uint80(b.rounds) * b.unitPerRound;
      batchNo = b.nextBatchNo;
    }
  }

  function internalGetCoveredRateBands(address insured, bool ignoreRecent) internal view returns (uint256[] memory rateBands) {
    Rounds.Demand[] storage demands = _demands[insured];
    uint256 demandLength = demands.length;
    if (demandLength == 0) {
      return rateBands;
    }

    Rounds.Coverage memory covered = _covered[insured];

    if (!ignoreRecent) {
      DemandedCoverage memory coverage;
      Rounds.CoveragePremium memory premium;

      while (covered.lastUpdateIndex < demandLength) {
        if (!_collectCoveredDemandSlot(demands[covered.lastUpdateIndex], coverage, covered, premium)) {
          break;
        }
      }
    }

    // the upper limit
    uint256 lastIndex = covered.lastUpdateIndex;
    uint256 unitCount = covered.lastUpdateRounds;
    uint256 bandCount = lastIndex;

    if (unitCount != 0) {
      bandCount++;
    } else if (lastIndex > 0) {
      unchecked {
        lastIndex--;
      }
    } else {
      return rateBands;
    }

    rateBands = new uint256[](bandCount);
    bandCount = 0;

    uint256 lastRate = uint256(1) << Rounds.DEMAND_RATE_BITS;

    Rounds.Demand memory d;
    for (;;) {
      d = demands[lastIndex];
      if (unitCount == 0) {
        unitCount = d.rounds;
      }
      unitCount *= d.unitPerRound;

      if (lastRate != d.premiumRate) {
        lastRate = d.premiumRate;
        rateBands[bandCount] = (lastRate << (256 - Rounds.DEMAND_RATE_BITS)) | unitCount;
        bandCount++;
      } else {
        rateBands[bandCount - 1] += unitCount;
      }

      if (lastIndex == 0) {
        break;
      }
      unchecked {
        lastIndex--;
      }
      unitCount = 0;
    }

    Arrays.truncateUint256(rateBands, bandCount);
  }

  error DemandMustBeCancelled();

  /// @dev Cancel ALL coverage for the insured, including in the partial state
  /// @dev Deletes the coverage information and demands of the insured
  /// @return coverage The coverage info of the insured. IS FINALIZED
  /// @return excessCoverage The new amount of excess coverage
  /// @return providedCoverage Amount of coverage provided before cancellation
  /// @return receivedCoverage Amount of coverage received from the sync before cancelling
  function internalCancelCoverage(address insured)
    internal
    returns (
      DemandedCoverage memory coverage,
      uint256 excessCoverage,
      uint256 providedCoverage,
      uint256 receivedCoverage,
      uint256 receivedPremium
    )
  {
    Rounds.InsuredEntry storage entry = _insureds[insured];

    if (entry.demandedUnits == 0) {
      return (coverage, 0, 0, 0, 0);
    }
    _removeFromPullable(insured, entry.nextBatchNo);

    Rounds.Coverage memory covered;
    Rounds.CoveragePremium memory premium;
    (coverage, covered, premium, receivedCoverage, receivedPremium) = _syncBeforeCancelCoverage(insured);

    Rounds.Demand[] storage demands = _demands[insured];
    Rounds.Demand memory d;
    PartialState memory part = _partial;

    if (covered.lastUpdateIndex < demands.length) {
      if (covered.lastUpdateIndex == demands.length - 1 && covered.lastUpdateBatchNo == part.batchNo && covered.lastPartialRoundNo == part.roundNo) {
        d = demands[covered.lastUpdateIndex];
      } else {
        revert DemandMustBeCancelled();
      }
    } else {
      Sanity.require(entry.demandedUnits == covered.coveredUnits);
    }

    providedCoverage = covered.coveredUnits * _unitSize;
    _pendingCancelledCoverageUnits += covered.coveredUnits - uint64(covered.lastPartialRoundNo) * d.unitPerRound;

    if (part.batchNo > 0) {
      _premiums[insured] = _cancelPremium(premium, coverage.totalPremium);
      // ATTN! There MUST be a call to _updateTimeMark AFTER _cancelPremium - this call is inside _cancelPartialCoverage
      excessCoverage = _cancelPartialCoverage(part, d);
    }

    entry.demandedUnits = 0;
    entry.nextBatchNo = 0;
    delete (_covered[insured]);
    delete (_demands[insured]);
  }

  /// @dev Sync the insured's amount of coverage and premium paid
  /// @return coverage FINAZLIED coverage amounts ONLY for the insured
  /// @return covered Updated coverage info from sync
  /// @return premium Total premium collected and rate after sync
  /// @return receivedCoverage FINALIZED amount of covered units during this sync
  function _syncBeforeCancelCoverage(address insured)
    private
    view
    returns (
      DemandedCoverage memory coverage,
      Rounds.Coverage memory covered,
      Rounds.CoveragePremium memory premium,
      uint256 receivedCoverage,
      uint256 receivedPremium
    )
  {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~uint256(0);

    (coverage, covered, premium) = internalGetCoveredDemand(params);
    Sanity.require(params.done);

    receivedCoverage = params.receivedCoverage;
    receivedPremium = params.receivedPremium;
  }

  /// @dev Cancel coverage in the partial state
  /// @return excessCoverage The new amount of excess coverage
  function _cancelPartialCoverage(PartialState memory part, Rounds.Demand memory d) private returns (uint128 excessCoverage) {
    Rounds.Batch storage partBatch = _batches[part.batchNo];
    Rounds.Batch memory b = partBatch;

    // Call to _updateTimeMark is MUST, because of _cancelPremium updating _poolPremium's timestamp
    _updateTimeMark(part, b.unitPerRound);

    if (d.unitPerRound == 0) {
      return 0;
    }
    Sanity.require(d.unitPerRound <= b.unitPerRound);

    {
      TimeMark storage mark = _marks[part.batchNo];
      uint192 coverageTW = mark.coverageTW;
      if (coverageTW > 0) {
        // reduce the integral summ proportionally - the relevant part was added to finalPremium already
        uint256 delta = _calcTimeMarkPortion(coverageTW, d.unitPerRound, b.unitPerRound);
        mark.coverageTW = uint192(coverageTW - delta);
      }
    }

    (partBatch.unitPerRound, partBatch.roundPremiumRateSum) = (
      b.unitPerRound -= d.unitPerRound,
      b.roundPremiumRateSum - uint56(d.premiumRate) * d.unitPerRound
    );

    if (b.unitPerRound == 0) {
      excessCoverage = part.roundCoverage;
      _partial.roundCoverage = part.roundCoverage = 0;
      _partial.roundNo = part.roundNo = 0;
    } else if (part.roundCoverage > 0) {
      excessCoverage = uint128(_unitSize) * b.unitPerRound;

      if (part.roundCoverage > excessCoverage) {
        (part.roundCoverage, excessCoverage) = (excessCoverage, part.roundCoverage - excessCoverage);
        _partial.roundCoverage = part.roundCoverage;
      }
    }
  }

  /// @dev Update the premium based on time elapsed and premium rate
  function _syncPremium(Rounds.CoveragePremium memory premium) private view returns (Rounds.CoveragePremium memory) {
    if (premium.lastUpdatedAt != 0) {
      premium.coveragePremium += uint96(premium.coveragePremiumRate) * (uint32(block.timestamp) - premium.lastUpdatedAt);
    }
    premium.lastUpdatedAt = uint32(block.timestamp);
    return premium;
  }

  /// @dev Cancel premium according to the parameters, and adjust the global pool's premium rate
  /// @param premium The premium info of the insured
  /// @param finalPremium The REAL amount of premium collected from the insured (multiplied by unitSize)
  /// @return A new CoveragePremium struct with the rate set to 0
  function _cancelPremium(Rounds.CoveragePremium memory premium, uint256 finalPremium) private returns (Rounds.CoveragePremium memory) {
    Rounds.CoveragePremium memory poolPremium = _syncPremium(_poolPremium);

    finalPremium = finalPremium.wadDiv(_unitSize).asUint96();

    poolPremium.coveragePremiumRate -= premium.coveragePremiumRate;
    poolPremium.coveragePremium += uint96(finalPremium - premium.coveragePremium);

    if (premium.lastUpdatedAt != poolPremium.lastUpdatedAt) {
      // avoid double-counting when premiuns are not synced
      poolPremium.coveragePremium -= uint96(premium.coveragePremiumRate) * (poolPremium.lastUpdatedAt - premium.lastUpdatedAt);
    }

    _poolPremium = poolPremium;

    return Rounds.CoveragePremium({coveragePremiumRate: 0, coveragePremium: uint96(finalPremium), lastUpdatedAt: poolPremium.lastUpdatedAt});
  }

  function _addToPullable(address insured, uint64 batchNo) private {
    _pullableDemands[batchNo].add(insured);
  }

  function _removeFromPullable(address insured, uint64 batchNo) private {
    _pullableDemands[batchNo].remove(insured);
  }

  function internalPullDemandCandidate(uint256 loopLimit, bool trimOnly) internal returns (address insured, uint256) {
    uint64 batchNo;
    uint64 pullableBatchNo = batchNo = _pullableBatchNo;
    if (batchNo == 0) {
      batchNo = 1;
    }

    for (; loopLimit > 0; ) {
      loopLimit--;

      Rounds.Batch storage batch = _batches[batchNo];
      if (!batch.state.isFull()) {
        break;
      }

      EnumerableSet.AddressSet storage demands = _pullableDemands[batchNo];
      for (uint256 n = demands.length(); n > 0; ) {
        n--;
        insured = demands.at(n);
        if (_insureds[insured].status == MemberStatus.Accepted) {
          if (!trimOnly) {
            demands.remove(insured);
          }
          break;
        }
        demands.remove(insured);
        insured = address(0);
        if (loopLimit == 0) {
          break;
        }
        loopLimit--;
      }
      if (insured != address(0)) {
        break;
      }

      uint64 nextBatchNo = batch.nextBatchNo;
      if (nextBatchNo == 0) {
        break;
      }
      batchNo = nextBatchNo;
    }

    if (pullableBatchNo != batchNo) {
      _pullableBatchNo = batchNo;
    }

    return (insured, loopLimit);
  }

  function internalOpenBatchRounds() internal view returns (uint256) {
    return _batches[_firstOpenBatchNo].rounds;
  }
}
