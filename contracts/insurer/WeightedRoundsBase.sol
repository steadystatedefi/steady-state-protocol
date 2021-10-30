// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../tools/math/WadRayMath.sol';
import '../interfaces/IInsurerPool.sol';

import 'hardhat/console.sol';

/*

UnitPremiumRate per sec * 365 days <= 1 WAD (i.e. 1 WAD = 100% of coverage p.a.)
=>> UnitPremiumRate is uint40
=>> RoundPremiumRate = UnitPremiumRate (40) * unitPerRound (16) = 56
=>> UnitAccumulatedPremiumRate = UnitPremiumRate (40) * timestamp (32) * unitPerRound (16) = 88
=>> PoolPremiumRate = UnitPremiumRate (40) * maxUnits (64) = 108
=>> PoolAccumulatedPremiumRate = PoolPremiumRate (108) * timestamp (32) = 140

*/

library Rounds {
  struct Demand {
    uint64 startBatchNo;
    uint40 premiumRate;
    uint24 rounds;
    uint16 unitPerRound;
  }

  struct InsuredConfig {
    // riskLevel, minPremiumRate
    uint32 maxShare;
    uint32 minUnits;
  }

  struct InsuredEntry {
    uint64 latestBatchNo;
    uint64 demandedUnits;
    bool hasMore;
  }

  struct Coverage {
    //    uint128 coveragePremiumRate;
    uint64 coveredUnits;
    uint64 lastUpdateIndex;
    //    uint64 lastFullBatchNo;
    //    uint192 totalCoveragePremium;
    uint32 lastUpdatedAt;
    uint24 lastUpdateRounds;
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
    /// @dev should be divided by unitPerRound to get the average rate
    uint56 roundPremiumRateSum;
    uint24 rounds;
    uint16 unitPerRound;
    State state;
  }

  function isFull(Batch memory b) internal pure returns (bool) {
    return b.state == State.Full;
  }

  function isOpen(Batch memory b) internal pure returns (bool) {
    return b.state <= State.ReadyMin;
  }

  function isUsable(Batch memory b) internal pure returns (bool) {
    return b.state >= State.ReadyMin && b.state <= State.Ready;
  }
}

abstract contract WeightedRoundsBase {
  using Rounds for Rounds.Batch;
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
    /// @dev amount of coverage in the partial round, must be zero when roundNo == batch size
    uint128 roundCoverage;
    /// @dev points either to a partial round or to the last full round when there is no other rounds
    /// @dev can ONLY be zero when there is no rounds (zero state)
    uint64 batchNo;
    /// @dev number of a partial round / also is the number of full rounds in the batch
    /// @dev when equals to batch size - then there is no partial round
    uint24 roundNo;
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

  struct AddCoverageDemandParams {
    address insured;
    uint40 premiumRate;
    uint32 loopLimit;
    bool hasMore;
    Rounds.InsuredConfig config;
  }

  function internalAddCoverageDemand(uint64 unitCount, AddCoverageDemandParams memory params)
    internal
    returns (uint64)
  {
    console.log('\ninternalAddCoverageDemand');
    Rounds.InsuredEntry memory entry = _onlyAcceptedInsured(params.insured);
    Rounds.Demand[] storage demands = _demands[params.insured];
    params.config = _configs[params.insured];

    if (unitCount == 0 || params.loopLimit == 0) {
      _insureds[params.insured].hasMore = params.hasMore;
      return unitCount;
    }

    entry.hasMore = params.hasMore;

    (uint64 nextBatch, bool isFirstOfOpen) = _findBatchToAppend(entry.latestBatchNo);
    uint64 totalUnitsBeforeBatch;
    Rounds.Demand memory demand;

    for (; unitCount > 0 && params.loopLimit > 0; ) {
      console.log('addDLoop', nextBatch, isFirstOfOpen, totalUnitsBeforeBatch);
      params.loopLimit--;

      uint64 thisBatch = nextBatch != 0 ? nextBatch : _appendBatch();

      Rounds.Batch memory b = _batches[thisBatch];
      console.log('batch', thisBatch, b.nextBatchNo);
      console.log('batch', thisBatch, b.rounds, b.unitPerRound);

      if (b.totalUnitsBeforeBatch >= totalUnitsBeforeBatch) {
        totalUnitsBeforeBatch = b.totalUnitsBeforeBatch;
      } else {
        b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
      }

      uint16 addPerRound;
      bool stop;
      (addPerRound, stop) = _addToBatch(unitCount, b, entry.demandedUnits, params);
      console.log('added0', addPerRound, b.rounds, b.unitPerRound);
      console.log('added1', uint256(b.state), b.totalUnitsBeforeBatch, b.roundPremiumRateSum);

      _batches[thisBatch] = b;

      if (isFirstOfOpen && b.isOpen()) {
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

      if (demand.unitPerRound == addPerRound) {
        demand.rounds += b.rounds;
      } else {
        if (demand.startBatchNo != 0) {
          demands.push(demand);
        }
        demand = Rounds.Demand({
          startBatchNo: thisBatch,
          rounds: b.rounds,
          unitPerRound: addPerRound,
          premiumRate: params.premiumRate
        });
      }

      entry.latestBatchNo = thisBatch;
      nextBatch = b.nextBatchNo;
    }

    _insureds[params.insured] = entry;

    if (demand.startBatchNo != 0) {
      demands.push(demand);
    }

    if (isFirstOfOpen) {
      _firstOpenBatch = 0;
    }

    return unitCount;
  }

  function _findBatchToAppend(uint64 latestBatchNo) internal returns (uint64 nextBatch, bool isFirstOfOpen) {
    uint64 firstOpen = _firstOpenBatch;
    if (firstOpen == 0) {
      // there are no open batches
      // TODO check addCoverage for the exhuastion case
      return (0, true);
    }

    if (latestBatchNo == 0 || (nextBatch = _batches[latestBatchNo].nextBatchNo) == 0 || !_batches[nextBatch].isOpen()) {
      nextBatch = firstOpen;
    }

    PartialState memory part = _partial;
    if (part.batchNo == nextBatch) {
      nextBatch = _splitBatch(nextBatch, part.roundCoverage == 0 ? part.roundNo : part.roundNo + 1);
    }
    isFirstOfOpen = nextBatch == firstOpen;
  }

  function _addToBatch(
    uint64 unitCount,
    Rounds.Batch memory b,
    uint64 demandedUnits,
    AddCoverageDemandParams memory params
  ) private returns (uint16 addPerRound, bool stop) {
    require(b.isOpen()); // TODO dev sanity check - remove later

    if (b.rounds == 0 || unitCount < b.rounds) {
      // split the batch or return the non-allocated units
      uint24 splitRounds = internalBatchSplit(b.rounds, demandedUnits, uint24(unitCount), params.config.minUnits);
      if (splitRounds == 0) {
        return (0, true);
      }
      require(unitCount >= splitRounds);

      if (b.rounds == 0) {
        // initialize an empty round
        b.rounds = splitRounds;
      } else {
        console.log('batchSplit-before', splitRounds, b.rounds, b.nextBatchNo);
        _splitBatch(splitRounds, b);
        console.log('batchSplit-after', b.rounds, b.nextBatchNo);
      }
    }

    (uint16 maxShareUnitsPerRound, uint16 minUnitsPerRound, uint16 maxUnitsPerRound) = internalRoundLimits(
      b.totalUnitsBeforeBatch,
      demandedUnits,
      params.config.maxShare
    );

    if (b.unitPerRound >= maxUnitsPerRound) {
      b.state = Rounds.State.Ready;
      return (0, false);
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
    b.roundPremiumRateSum += uint56(params.premiumRate) * addPerRound;

    if (b.unitPerRound >= maxUnitsPerRound) {
      b.state = Rounds.State.Ready;
    } else if (b.unitPerRound >= minUnitsPerRound) {
      b.state = Rounds.State.ReadyMin;
    }
    return (addPerRound, false);
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
    );

  function internalBatchSplit(
    uint24 batchRounds,
    uint64 demandedUnits,
    uint24 remainingUnits,
    uint64 minUnits
  ) internal virtual returns (uint24 splitRounds);

  function _splitBatch(uint64 batchNo, uint24 remainingRounds) private returns (uint64 newBatchNo) {
    if (remainingRounds == 0) {
      return batchNo;
    }
    Rounds.Batch memory b = _batches[batchNo];
    _splitBatch(remainingRounds, b);
    _batches[batchNo] = b;

    return b.nextBatchNo;
  }

  function _splitBatch(uint24 remainingRounds, Rounds.Batch memory b) private {
    if (b.rounds == remainingRounds) return;
    require(b.rounds > remainingRounds, 'split beyond size');

    uint64 newBatchNo = ++_batchCount;
    // console.log(b.rounds, b.unitPerRound, b.nextBatchNo, b.totalUnitsBeforeBatch);

    _batches[newBatchNo] = Rounds.Batch({
      nextBatchNo: b.nextBatchNo,
      totalUnitsBeforeBatch: b.totalUnitsBeforeBatch + remainingRounds * b.unitPerRound,
      rounds: b.rounds - remainingRounds,
      unitPerRound: b.unitPerRound,
      state: b.state,
      roundPremiumRateSum: b.roundPremiumRateSum
    });

    b.rounds = remainingRounds;
    if (b.nextBatchNo == 0) {
      _latestBatch = newBatchNo;
    }
    b.nextBatchNo = newBatchNo;
    // console.log(b.rounds, b.unitPerRound, b.nextBatchNo, b.totalUnitsBeforeBatch);
  }

  function _appendBatch() private returns (uint64 newBatchNo) {
    uint64 batchNo = _latestBatch;
    if (batchNo == 0) {
      newBatchNo = ++_batchCount;
      require(newBatchNo == 1);
      _partial.batchNo = 1;
      _firstOpenBatch = 1;
    } else {
      Rounds.Batch memory b = _batches[batchNo];
      if (b.rounds == 0) {
        return batchNo;
      }

      newBatchNo = ++_batchCount;

      _batches[batchNo].nextBatchNo = newBatchNo;
      _batches[newBatchNo].totalUnitsBeforeBatch = b.totalUnitsBeforeBatch + b.unitPerRound * b.rounds;
    }

    _latestBatch = newBatchNo;
    return newBatchNo;
  }

  // struct Coverage {
  //   uint128 coveragePremiumRate;
  //   uint192 totalCoveragePremium;
  //   uint32 lastUpdatedAt;

  //   uint64 coveredUnits;
  //   uint64 lastUpdateIndex;
  //   uint24 lastUpdateRounds;
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

    uint24 skipRounds = covered.lastUpdateRounds;
    covered.lastUpdateRounds = 0;

    for (; covered.lastUpdateIndex < demands.length; covered.lastUpdateIndex++) {
      Rounds.Demand memory d = demands[covered.lastUpdateIndex];
      console.log('demand', d.startBatchNo, d.rounds, skipRounds);

      uint24 fullRounds;
      while (d.rounds > fullRounds && d.startBatchNo > 0) {
        Rounds.Batch memory b = _batches[d.startBatchNo];

        if (!b.isFull()) break;
        require(b.rounds > 0);
        fullRounds += b.rounds;
        d.startBatchNo = b.nextBatchNo;

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
      console.log('demandRounds', d.rounds, fullRounds);

      bool stop;
      if (d.rounds > fullRounds) {
        require(d.startBatchNo != 0);

        PartialState memory part = _partial;
        console.log('check', part.batchNo, d.startBatchNo);
        if (part.batchNo == d.startBatchNo) {
          fullRounds += part.roundNo;
          covered.lastUpdateRounds = fullRounds;

          coverage.pendingCovered =
            (uint256(part.roundCoverage) * d.unitPerRound) /
            _batches[d.startBatchNo].unitPerRound;
        } else {
          require(fullRounds == 0);
        }
        stop = true;
      } else {
        require(d.rounds == fullRounds);
      }

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

  function internalGetTotals() internal view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    PartialState memory part = _partial;
    uint64 thisBatch = part.batchNo;
    if (thisBatch == 0) return (coverage, total);

    Rounds.Batch memory b = _batches[thisBatch];
    console.log('batch0', thisBatch, b.nextBatchNo, b.rounds);
    console.log('batch1', part.roundNo);

    coverage.totalCovered = b.totalUnitsBeforeBatch + uint256(part.roundNo) * b.unitPerRound;
    coverage.totalDemand = b.totalUnitsBeforeBatch + uint256(b.rounds) * b.unitPerRound;
    coverage.pendingCovered = part.roundCoverage;
    total.batchCount = 1;

    if (b.isUsable()) {
      total.usableRounds = b.rounds - part.roundNo;
      total.totalCoverable = uint256(total.usableRounds) * b.unitPerRound;
    }
    if (b.isOpen()) {
      total.openRounds += b.rounds - part.roundNo;
    }

    while (b.nextBatchNo != 0) {
      thisBatch = b.nextBatchNo;
      b = _batches[b.nextBatchNo];
      console.log('batch', thisBatch, b.nextBatchNo);

      total.batchCount++;
      coverage.totalDemand += uint256(b.rounds) * b.unitPerRound;

      if (b.isUsable()) {
        total.usableRounds += b.rounds;
        total.totalCoverable += uint256(b.rounds) * b.unitPerRound;
      }

      if (b.isOpen()) {
        total.openRounds += b.rounds;
      }
    }

    // TODO premium
    coverage.totalCovered *= _unitSize;
    coverage.totalDemand *= _unitSize;
    total.totalCoverable = total.totalCoverable * _unitSize - coverage.pendingCovered;
  }

  function receiveDemandedCoverage(address insured)
    external
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    (receivedCoverage, coverage, _covered[insured]) = _collectCoveredDemand(insured, _onlyAcceptedInsured(insured));
    // TODO transfer receivedCoverage to the insured
    return (receivedCoverage, coverage);
  }

  struct AddCoverageParams {
    uint64 openBatchNo;
    bool openBatchUpdated;
    bool batchUpdated;
  }

  function internalAddCoverage(uint256 amount, uint256 loopLimit)
    internal
    returns (uint256 remainingAmount, uint256 remainingLoopLimit)
  {
    PartialState memory part = _partial;

    if (amount == 0 || loopLimit == 0 || part.batchNo == 0) {
      return (amount, loopLimit);
    }

    Rounds.Batch memory b;
    AddCoverageParams memory params;
    (amount, loopLimit, b) = _addCoverage(amount, loopLimit, part, params);
    if (params.batchUpdated) {
      _batches[part.batchNo] = b;
    }
    if (params.openBatchUpdated) {
      _firstOpenBatch = params.openBatchNo;
    }
    _partial = part;
    console.log('partial3', part.batchNo, part.roundNo, part.roundCoverage);
    return (amount, loopLimit);
  }

  function _addCoverage(
    uint256 amount,
    uint256 loopLimit,
    PartialState memory part,
    AddCoverageParams memory params
  )
    internal
    returns (
      uint256 remainingAmount,
      uint256 remainingLoopLimit,
      Rounds.Batch memory b
    )
  {
    b = _batches[part.batchNo];

    if (part.roundCoverage > 0) {
      require(b.isUsable(), 'wrong partial round'); // sanity check
      _updateTimeMark(part.batchNo, part, b.unitPerRound);

      uint256 maxRoundCoverage = uint256(_unitSize) * b.unitPerRound;
      uint256 vacant = maxRoundCoverage - part.roundCoverage;
      if (amount < vacant) {
        part.roundCoverage += uint128(amount);
        return (0, loopLimit - 1, b);
      }
      part.roundCoverage = 0;
      part.roundNo++;
      amount -= vacant;
    } else if (!b.isUsable()) {
      return (amount, loopLimit - 1, b);
    }

    params.openBatchNo = _firstOpenBatch;
    for (; loopLimit > 0; ) {
      loopLimit--;
      require(b.unitPerRound > 0, 'empty round');

      if (part.roundNo >= b.rounds) {
        require(part.roundNo == b.rounds);
        require(part.roundCoverage == 0);

        if (b.state != Rounds.State.Full || params.batchUpdated) {
          b.state = Rounds.State.Full;
          _batches[part.batchNo] = b;
          params.batchUpdated = false;
        }

        if (part.batchNo == params.openBatchNo) {
          params.openBatchNo = b.nextBatchNo;
          params.openBatchUpdated = true;
        }

        if (b.nextBatchNo == 0) break;

        // DO NOT do like this here:  part = PartialState({batchNo: b.nextBatchNo, roundNo: 0, roundCoverage: 0});
        part.batchNo = b.nextBatchNo;
        part.roundNo = 0;
        part.roundCoverage = 0;
        console.log('partial0', part.batchNo, part.roundNo, part.roundCoverage);

        {
          uint64 totalUnitsBeforeBatch = b.totalUnitsBeforeBatch + uint64(b.rounds) * b.unitPerRound;

          b = _batches[part.batchNo];

          if (totalUnitsBeforeBatch != b.totalUnitsBeforeBatch) {
            require(totalUnitsBeforeBatch >= b.totalUnitsBeforeBatch);
            b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
            params.batchUpdated = true;
          }
        }

        if (amount == 0) {
          return (0, loopLimit, b);
        }

        if (!b.isUsable()) {
          if (!internalUseNotReadyBatch(b)) {
            console.log('partial1', part.batchNo, part.roundNo, part.roundCoverage);
            return (amount, loopLimit, b);
          }
          b.state = Rounds.State.ReadyMin;
          params.batchUpdated = true;
        }
        _initTimeMark(part.batchNo);
        continue;
      }

      if (amount == 0) {
        return (0, loopLimit, b);
      }

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

    return (amount, loopLimit, b);
  }

  function internalUseNotReadyBatch(Rounds.Batch memory) internal virtual returns (bool) {
    return false;
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

  struct Dump {
    uint64 batchCount;
    uint64 latestBatch;
    /// @dev points to an earliest round that is open, can be zero when all rounds are full
    uint64 firstOpenBatch;
    PartialState part;
    Rounds.Batch[] batches;
  }

  function _dump() internal view returns (Dump memory dump) {
    dump.batchCount = _batchCount;
    dump.latestBatch = _latestBatch;
    dump.firstOpenBatch = _firstOpenBatch;
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

  function cancelCoverageDemand(uint256 unitCount, bool hasMore) external returns (uint256 cancelledUnits) {}

  // function _cancelCoveredDemand(address insured, uint256 unitCount)
  //   private
  //   view
  //   returns (uint256 remainingUnits)
  // {
  //   Rounds.Demand[] storage demands = _demands[insured];
  //   if (demands.length == 0) {
  //     return unitCount;
  //   }
  //   Rounds.Coverage memory covered = _covered[insured];
  //   PartialState memory part = _partial;

  //   for (uint i = demands.length - 1; i > covered.lastUpdateIndex; i--) {
  //     Rounds.Demand memory d = demands[i];
  //     require(d.startBatchNo != 0);
  //     Rounds.Batch memory b = _batches[d.startBatchNo];

  //     if (b.state.isFull() && part.batchNo != d.startBatchNo) {

  //     }

  //     if (b.state.isOpen() && part.batchNo != d.startBatchNo) {
  //       // simple case - all rounds are open
  //       uint24 fullRounds;
  //       while (d.rounds > fullRounds && d.startBatchNo > 0) {

  //         if (!b.state.isFull()) break;
  //         require(b.rounds > 0);
  //         fullRounds += b.rounds;
  //         expectedBatchNo = d.startBatchNo = b.nextBatchNo;
  //       }
  //     }
  //   }
  //   return (receivedCoverage, coverage, covered);
  // }
}
