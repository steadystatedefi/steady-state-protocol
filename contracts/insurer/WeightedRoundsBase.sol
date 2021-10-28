// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../tools/math/WadRayMath.sol';
import '../interfaces/IInsurerPool.sol';

library Rounds {
  struct Demand {
    uint128 premiumRate;
    uint64 startBatchNo;
    uint24 rounds;
    uint16 unitPerRound;
  }

  struct InsuredConfig {
    // riskLevel, minPremiumRate
    uint32 maxShare;
    uint32 minUnits;
  }

  struct InsuredEntry {
    uint64 earliestBatchNo;
    uint64 latestBatchNo;
    uint64 demandedUnits;
    bool hasMore;
  }

  struct Coverage {
    uint128 coveragePremiumRate;
    uint64 coveredUnits;
    uint64 openDemandIndex;
    uint192 totalCoveragePremium;
    uint32 lastUpdatedAt;
    uint24 coveredDemandRounds;
  }

  enum State {
    Draft,
    ReadyMin,
    Ready,
    Full
  }

  struct Batch {
    uint64 nextBatchNo;
    /// @dev totalUnitsBeforeBatch value may be lower for non-ready batches
    uint64 totalUnitsBeforeBatch;
    uint24 rounds;
    uint16 unitPerRound;
    State state;
    /// @dev should be divided by unitPerRound to get the average rate
    uint128 roundPremiumRateSum;
  }

  function isFull(State s) internal pure returns (bool) {
    return s == State.Full;
  }

  function isOpen(State s) internal pure returns (bool) {
    return s <= State.ReadyMin;
  }

  function isUsable(State s) internal pure returns (bool) {
    return s >= State.ReadyMin && s <= State.Ready;
  }
}

abstract contract WeightedRoundsBase {
  using Rounds for Rounds.State;
  using WadRayMath for uint256;

  uint256 private immutable _unitSize;

  constructor(uint256 unitSize) {
    require(unitSize > 0);
    _unitSize = unitSize;
  }

  mapping(address => Rounds.InsuredEntry) private _insureds;
  mapping(address => Rounds.InsuredConfig) private _configs;
  mapping(address => Rounds.Demand[]) private _demands;
  mapping(address => Rounds.Coverage) private _covered;

  /// @dev Draft round can NOT receive coverage, more units can be added, always unbalanced
  /// @dev Ready round can receive coverage, more units can NOT be added, balanced
  /// @dev ReadyCut is a Ready round with some units cancelled, can receive coverage, more units can be added, unbalanced
  /// @dev Partial round (exclusive state) receives coverage, more units can NOT be added
  /// @dev Full round can NOT receive coverage, more units can NOT be added - full rounds are summed up and ignored further

  mapping(uint64 => Rounds.Batch) private _batches;
  /// @dev total number of batches
  uint64 private _batchCount;
  uint64 private _latestBatch;
  /// @dev points to an earliest round that is open, can be zero when all rounds are full
  uint64 private _firstOpenBatch;

  struct PartialState {
    /// @dev points either to a partial round or to the last full round when there is no other rounds
    /// @dev can ONLY be zero when there is no rounds (zero state)
    uint64 batchNo;
    /// @dev number of a partial round / also is the number of full rounds in the batch
    /// @dev when equals to batch size - then there is no partial round
    uint24 roundNo;
    /// @dev amount of coverage in the partial round, must be zero when roundNo == batch size
    uint128 roundCoverage;
  }
  PartialState private _partial;

  struct TimeMark {
    uint192 coverageTWA;
    uint32 timestamp;
    uint32 duration;
  }
  mapping(uint64 => TimeMark) private _marks;

  uint256 private _unusedCoverage; // TODO

  function coverageUnitSize() external view returns (uint256) {
    return _unitSize;
  }

  function _onlyAcceptedInsured(address insured) internal view virtual returns (Rounds.InsuredEntry storage entry) {
    entry = _insureds[insured];
    //    require(entry.status == InsuredStatus.Accepted);
  }

  function internalAddCoverageDemand(
    address insured,
    uint64 unitCount,
    uint128 premiumRate,
    bool hasMore,
    uint64 loopLimit
  ) internal returns (uint64 residualCount, uint64 remainingLoopLimit) {
    Rounds.InsuredEntry memory entry = _onlyAcceptedInsured(insured);
    Rounds.Demand[] storage demands = _demands[insured];
    Rounds.InsuredConfig memory config = _configs[insured];

    if (unitCount == 0 || loopLimit == 0) {
      _insureds[insured].hasMore = hasMore;
      return (unitCount, loopLimit);
    }

    entry.hasMore = hasMore;

    // internalCheckPremium(insured, batches[i].premiumRate);

    uint64 nextBatch;
    bool isFirstOfOpen;
    {
      uint64 openBatchNo = _firstOpenBatch;
      if (entry.latestBatchNo != 0 && entry.latestBatchNo != openBatchNo) {
        nextBatch = _batches[entry.latestBatchNo].nextBatchNo;
      }

      if (nextBatch == 0 || !_batches[nextBatch].state.isOpen()) {
        if (openBatchNo != 0) {
          PartialState memory part = _partial;
          if (part.batchNo != openBatchNo) {
            nextBatch = openBatchNo;
          } else {
            nextBatch = _splitBatch(openBatchNo, part.roundCoverage == 0 ? part.roundNo : part.roundNo + 1);
          }
        } else {
          nextBatch = 0;
        }
        isFirstOfOpen = true;
      }
    }

    uint64 totalUnitsBeforeBatch;

    for (; unitCount > 0 && loopLimit > 0; ) {
      loopLimit--;

      uint64 thisBatch = nextBatch != 0 ? nextBatch : _appendBatch();
      if (entry.earliestBatchNo == 0) {
        entry.earliestBatchNo = thisBatch;
      }

      Rounds.Batch memory b = _batches[thisBatch];
      {
        uint64 before = b.totalUnitsBeforeBatch;
        if (before >= totalUnitsBeforeBatch) {
          totalUnitsBeforeBatch = before;
        } else {
          b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
        }
      }

      uint16 addPerRound;
      bool stop;
      (addPerRound, stop, b) = _addToBatch(unitCount, premiumRate, b, entry.demandedUnits, config);

      _batches[thisBatch] = b;

      if (isFirstOfOpen && b.state.isOpen()) {
        _firstOpenBatch = thisBatch;
        isFirstOfOpen = false;
      }

      if (stop) {
        require(addPerRound == 0);
        break;
      }

      if (addPerRound > 0) {
        uint64 addedUnits = uint64(addPerRound) * b.rounds;
        unitCount -= addedUnits;
        entry.demandedUnits += addedUnits;
      }

      totalUnitsBeforeBatch += b.unitPerRound * b.rounds;

      demands.push(
        Rounds.Demand({startBatchNo: thisBatch, rounds: b.rounds, unitPerRound: addPerRound, premiumRate: premiumRate})
      );

      entry.latestBatchNo = thisBatch;
      nextBatch = b.nextBatchNo;
    }

    _insureds[insured] = entry;

    if (isFirstOfOpen) {
      _firstOpenBatch = 0;
    }

    return (unitCount, loopLimit);
  }

  function _addToBatch(
    uint64 unitCount,
    uint128 premiumRate,
    Rounds.Batch memory b,
    uint64 demandedUnits,
    Rounds.InsuredConfig memory config
  )
    private
    returns (
      uint16 addPerRound,
      bool stop,
      Rounds.Batch memory
    )
  {
    require(b.state.isOpen()); // TODO dev sanity check - remove later

    if (b.rounds == 0 || unitCount < b.rounds) {
      // split the batch or return the non-allocated units
      uint24 splitRounds = internalBatchSplit(b.rounds, demandedUnits, uint24(unitCount), config.minUnits);
      if (splitRounds == 0) {
        return (0, true, b);
      }
      require(unitCount >= splitRounds);

      if (b.rounds == 0) {
        // initialize an empty round
        b.rounds = splitRounds;
      } else {
        (, b) = _splitBatch(splitRounds, b);
      }
    }

    (uint16 maxShareUnitsPerRound, uint16 minUnitsPerRound, uint16 maxUnitsPerRound) = internalRoundLimits(
      b.totalUnitsBeforeBatch,
      demandedUnits,
      config.maxShare
    );

    if (b.unitPerRound >= maxUnitsPerRound) {
      b.state = Rounds.State.Ready;
      return (0, false, b);
    }

    addPerRound = maxUnitsPerRound - b.unitPerRound;
    if (addPerRound > maxShareUnitsPerRound) {
      addPerRound = maxShareUnitsPerRound;
    }
    uint64 n = unitCount / b.rounds;
    if (addPerRound > n) {
      addPerRound = uint16(n);
    }
    require(addPerRound > 0);

    b.unitPerRound += addPerRound;
    b.roundPremiumRateSum += uint128(premiumRate) * addPerRound;

    if (b.unitPerRound >= maxUnitsPerRound) {
      b.state = Rounds.State.Ready;
    } else if (b.unitPerRound >= minUnitsPerRound && b.state < Rounds.State.ReadyMin) {
      b.state == Rounds.State.ReadyMin;
    }
    return (addPerRound, false, b);
  }

  function internalRoundLimits(
    uint64 totalUnitsBeforeBatch,
    uint64 demandedUnits,
    uint256 maxShare
  )
    internal
    virtual
    returns (
      uint16 maxAddUnitsPerRound,
      uint16 minUnitsPerRound,
      uint16 maxUnitsPerRound
    )
  {
    totalUnitsBeforeBatch;
    demandedUnits;
    maxShare;
    return (1, 8, 10);
  }

  function internalBatchSplit(
    uint24 batchRounds,
    uint64 demandedUnits,
    uint24 remainingUnits,
    uint64 minUnits
  ) internal virtual returns (uint24 splitRounds) {
    minUnits;
    batchRounds;
    demandedUnits;
    return remainingUnits;
  }

  function _splitBatch(uint64 batchNo, uint24 remainingRounds) private returns (uint64 newBatchNo) {
    if (remainingRounds == 0) {
      return batchNo;
    }
    (newBatchNo, _batches[batchNo]) = _splitBatch(remainingRounds, _batches[batchNo]);
    return newBatchNo;
  }

  function _splitBatch(uint24 remainingRounds, Rounds.Batch memory b)
    private
    returns (uint64 newBatchNo, Rounds.Batch memory b2)
  {
    if (b.rounds == remainingRounds) {
      return (b.nextBatchNo, b);
    }
    require(b.rounds > remainingRounds, 'split beyond size');

    newBatchNo = ++_batchCount;
    b2 = b;

    b2.rounds = remainingRounds;
    b2.nextBatchNo = newBatchNo;

    b.rounds -= remainingRounds;
    b.totalUnitsBeforeBatch += remainingRounds * b.unitPerRound;
    _batches[newBatchNo] = b;
    return (newBatchNo, b2);
  }

  function _appendBatch() private returns (uint64 newBatchNo) {
    uint64 batchNo = _latestBatch;
    if (batchNo == 0) {
      newBatchNo = ++_batchCount;
      require(newBatchNo == 1);
      _partial.batchNo = 1;
      _firstOpenBatch = 1;

      return newBatchNo;
    }

    Rounds.Batch memory b = _batches[batchNo];
    if (b.rounds == 0) {
      return batchNo;
    }

    newBatchNo = ++_batchCount;

    _batches[batchNo].nextBatchNo = newBatchNo;
    _batches[newBatchNo].totalUnitsBeforeBatch = b.totalUnitsBeforeBatch + b.unitPerRound * b.rounds;

    return newBatchNo;
  }

  // struct Coverage {
  //   uint128 coveragePremiumRate;
  //   uint192 totalCoveragePremium;
  //   uint32 lastUpdatedAt;

  //   uint64 coveredUnits;
  //   uint64 openDemandIndex;
  //   uint24 coveredDemandRounds;
  // }

  function _collectCoveredDemand(address insured, Rounds.InsuredEntry storage entry)
    private
    view
    returns (
      uint256 receivedCoverage,
      DemandedCoverage memory coverage,
      Rounds.Coverage memory covered
    )
  {
    Rounds.Demand[] storage demands = _demands[insured];
    covered = _covered[insured];
    receivedCoverage = covered.coveredUnits;

    uint64 expectedBatchNo;
    uint24 skipRounds = covered.coveredDemandRounds;

    for (; covered.openDemandIndex < demands.length; covered.openDemandIndex++) {
      Rounds.Demand memory d = demands[covered.openDemandIndex];
      if (expectedBatchNo != 0) {
        require(expectedBatchNo == d.startBatchNo); // sanity check
      }

      uint24 fullRounds;
      while (d.rounds > fullRounds && d.startBatchNo > 0) {
        Rounds.Batch memory b = _batches[d.startBatchNo];

        if (!b.state.isFull()) break;
        require(b.rounds > 0);
        fullRounds += b.rounds;
        expectedBatchNo = d.startBatchNo = b.nextBatchNo;

        // {
        //   TimeMark memory mark = _marks[d.startBatchNo];
        //   uint256 totalCoveragePremium = covered.totalCoveragePremium;
        //   if (covered.lastUpdatedAt != 0) {
        //     uint32 gap = mark.timestamp - covered.lastUpdatedAt - mark.duration;
        //     totalCoveragePremium += uint256(covered.coveragePremiumRate) * gap;
        //   }
        //   covered.lastUpdatedAt = mark.timestamp;

        //   totalCoveragePremium += uint256(d.premiumRate).rayMul(uint256(mark.coverageTWA) * d.unitPerRound);
        //   covered.totalCoveragePremium = uint192(totalCoveragePremium);

        //   uint256 rate = uint256(_unitSize) * b.rounds;
        //   rate = covered.coveragePremiumRate + rate.rayMul(d.premiumRate) * d.unitPerRound;
        //   covered.coveragePremiumRate = uint128(rate);
        // }
      }

      bool stop;
      if (d.rounds > fullRounds) {
        require(d.startBatchNo != 0);

        PartialState memory part = _partial;
        require(part.batchNo == d.startBatchNo);

        fullRounds += part.roundNo;
        coverage.pendingCovered =
          (uint256(part.roundCoverage) * d.unitPerRound) /
          _batches[d.startBatchNo].unitPerRound;
        stop = true;
      }

      covered.coveredDemandRounds = fullRounds;
      covered.coveredUnits += fullRounds - skipRounds;
      skipRounds = 0;

      if (stop) break;
    }
    // TODO collect premium data

    coverage.totalDemand = uint256(_unitSize) * entry.demandedUnits;
    coverage.totalCovered += uint256(_unitSize) * covered.coveredUnits;
    receivedCoverage = uint256(_unitSize) * (covered.coveredUnits - receivedCoverage);

    return (receivedCoverage, coverage, covered);
  }

  function getCoverageDemand(address insured)
    external
    view
    returns (uint256 availableCoverage, DemandedCoverage memory coverage)
  {
    (availableCoverage, coverage, ) = _collectCoveredDemand(insured, _onlyAcceptedInsured(insured));
    return (availableCoverage, coverage);
  }

  function receiveDemandedCoverage(address insured)
    external
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    (receivedCoverage, coverage, _covered[insured]) = _collectCoveredDemand(insured, _onlyAcceptedInsured(insured));
    // TODO transfer receivedCoverage to the insured
    return (receivedCoverage, coverage);
  }

  function internalAddCoverage(uint256 amount, uint64 loopLimit)
    internal
    returns (uint256 remainingAmount, uint64 remainingLoopLimit)
  {
    PartialState memory part = _partial;

    if (amount == 0 || loopLimit == 0 || part.batchNo == 0) {
      return (amount, loopLimit);
    }

    Rounds.Batch memory b = _batches[part.batchNo];
    if (part.roundCoverage > 0) {
      require(b.state.isUsable(), 'wrong partial round'); // sanity check
      _updateTimeMark(part.batchNo, part, b.unitPerRound);

      uint256 maxRoundCoverage = uint256(_unitSize) * b.unitPerRound;
      uint256 vacant = maxRoundCoverage - part.roundCoverage;
      if (amount < vacant) {
        _partial.roundCoverage = part.roundCoverage + uint128(amount);
        return (0, loopLimit - 1);
      }
      part.roundCoverage = 0;
      part.roundNo++;
      amount -= vacant;
    } else if (!b.state.isUsable()) {
      return (amount, loopLimit - 1);
    }

    uint64 openBatchNo = _firstOpenBatch;
    for (; loopLimit > 0; ) {
      loopLimit--;
      require(b.unitPerRound > 0, 'empty round');

      if (part.roundNo >= b.rounds) {
        require(part.roundNo == b.rounds);
        require(part.roundCoverage == 0);

        b.state = Rounds.State.Full;

        if (part.batchNo == openBatchNo) {
          openBatchNo = b.nextBatchNo;
        }

        if (b.nextBatchNo == 0) break;
        part = PartialState({batchNo: b.nextBatchNo, roundNo: 0, roundCoverage: 0});

        if (amount == 0) break;

        b = _batches[part.batchNo];
        if (!b.state.isUsable()) {
          return (amount, loopLimit);
        }
        _initTimeMark(part.batchNo);
        continue;
      }
      if (amount == 0) break;

      uint256 maxRoundCoverage = uint256(_unitSize) * b.unitPerRound;
      uint256 n = amount / maxRoundCoverage;

      uint24 vacantRounds = b.rounds - part.roundNo;
      require(vacantRounds > 0);

      if (n < vacantRounds) {
        part.roundNo += uint24(n);
        part.roundCoverage = uint128(amount - maxRoundCoverage * n);
        amount = 0;
        break;
      }

      part.roundNo = b.rounds;
      amount -= maxRoundCoverage * vacantRounds;
    }

    _firstOpenBatch = openBatchNo;
    _partial = part;
    return (amount, loopLimit);
  }

  function _initTimeMark(uint64 batchNo) private {
    require(batchNo != 0);
    require(_marks[batchNo].timestamp == 0);
    _marks[batchNo] = TimeMark({coverageTWA: 0, timestamp: uint32(block.timestamp), duration: 0});
  }

  function _updateTimeMark(
    uint64 batchNo,
    PartialState memory part,
    uint256 batchUnitPerRound
  ) private {
    require(batchNo != 0);
    TimeMark memory mark = _marks[batchNo];
    if (mark.timestamp == 0) {
      _marks[batchNo] = TimeMark({coverageTWA: 0, timestamp: uint32(block.timestamp), duration: 0});
      return;
    }

    uint32 duration = uint32(block.timestamp - mark.timestamp);
    if (duration == 0) return;

    uint256 coverageTWA = mark.coverageTWA +
      (uint256(_unitSize) * part.roundNo + part.roundCoverage / batchUnitPerRound) *
      duration;
    require(coverageTWA <= type(uint192).max);
    mark.coverageTWA = uint192(coverageTWA);

    mark.duration += duration;
    mark.timestamp = uint32(block.timestamp);

    _marks[batchNo] = mark;
  }

  // function internalCheckPremium(address insured, uint256 premium) private {}

  function cancelCoverageDemand(uint256 unitCount, bool hasMore) external returns (uint256 cancelledUnits) {}
}
