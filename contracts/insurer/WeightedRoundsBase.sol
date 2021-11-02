// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../interfaces/IInsurerPool.sol';
import './Rounds.sol';

import 'hardhat/console.sol';

abstract contract WeightedRoundsBase {
  using Rounds for Rounds.Batch;
  using WadRayMath for uint256;

  uint256 private immutable _unitSize;

  constructor(uint256 unitSize) {
    require(unitSize > 0);
    _unitSize = unitSize;
  }

  mapping(address => Rounds.InsuredEntry) private _insureds;
  mapping(address => Rounds.Demand[]) private _demands;
  mapping(address => Rounds.Coverage) private _covered;
  mapping(address => Rounds.CoveragePremium) private _premiums;

  mapping(uint64 => Rounds.Batch) private _batches;
  /// @dev total number of batches
  uint64 private _batchCount;
  uint64 private _latestBatchNo;
  /// @dev points to an earliest round that is open, can be zero when all rounds are full
  uint64 private _firstOpenBatchNo;
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
  PartialState private _partial;

  struct TimeMark {
    uint192 coverageTW;
    uint32 timestamp;
    uint32 duration;
  }
  mapping(uint64 => TimeMark) private _marks;

  function coverageUnitSize() public view returns (uint256) {
    return _unitSize;
  }

  struct AddCoverageDemandParams {
    uint256 loopLimit;
    address insured;
    uint40 premiumRate;
    bool hasMore;
  }

  function internalAddCoverageDemand(uint64 unitCount, AddCoverageDemandParams memory params)
    internal
    returns (uint64)
  {
    console.log('\ninternalAddCoverageDemand');
    Rounds.InsuredEntry memory entry = _insureds[params.insured];
    Rounds.Demand[] storage demands = _demands[params.insured];

    if (unitCount == 0 || params.loopLimit == 0) {
      _insureds[params.insured].hasMore = params.hasMore;
      return unitCount;
    }

    entry.hasMore = params.hasMore;

    (uint64 nextBatch, bool isFirstOfOpen) = _findBatchToAppend(entry.latestBatchNo);
    uint64 totalUnitsBeforeBatch;

    // TODO try to reuse the previous Demand slot from storage
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
      (addPerRound, stop) = _addToBatch(unitCount, b, entry, params);
      console.log('added0', addPerRound, b.rounds, b.unitPerRound);
      console.log('added1', uint256(b.state), b.totalUnitsBeforeBatch, b.roundPremiumRateSum);

      _batches[thisBatch] = b;

      if (isFirstOfOpen && b.isOpen()) {
        _firstOpenBatchNo = thisBatch;
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

      if (_addToSlot(demand, demands, addPerRound, b.rounds)) {
        demand.startBatchNo = thisBatch;
        demand.premiumRate = params.premiumRate;
      }

      entry.latestBatchNo = thisBatch;
      nextBatch = b.nextBatchNo;
    }

    _insureds[params.insured] = entry;

    if (demand.startBatchNo != 0) {
      demands.push(demand);
    }

    if (isFirstOfOpen) {
      _firstOpenBatchNo = 0;
    }

    return unitCount;
  }

  function _addToSlot(
    Rounds.Demand memory demand,
    Rounds.Demand[] storage demands,
    uint16 addPerRound,
    uint24 batchRounds
  ) private returns (bool) {
    if (demand.unitPerRound == addPerRound) {
      uint24 t;
      unchecked {
        t = batchRounds + demand.rounds;
      }
      if (t >= batchRounds) {
        demand.rounds = t;
        return false;
      }
      demand.rounds = type(uint24).max;
      batchRounds = t + 1;
    }

    if (demand.startBatchNo != 0) {
      demands.push(demand);
    }
    demand.rounds = batchRounds;
    demand.unitPerRound = addPerRound;
    return true;
  }

  function _findBatchToAppend(uint64 latestBatchNo) private returns (uint64 nextBatch, bool isFirstOfOpen) {
    uint64 firstOpen = _firstOpenBatchNo;
    if (firstOpen == 0) {
      // there are no open batches
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
    Rounds.InsuredEntry memory entry,
    AddCoverageDemandParams memory params
  ) private returns (uint16 addPerRound, bool stop) {
    require(b.isOpen()); // TODO dev sanity check - remove later

    if (b.rounds == 0 || unitCount < b.rounds) {
      // split the batch or return the non-allocated units
      uint24 splitRounds = internalBatchSplit(b.rounds, entry.demandedUnits, uint24(unitCount), entry.minUnits);
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
      entry.demandedUnits,
      entry.maxShare
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
      _latestBatchNo = newBatchNo;
    }
    b.nextBatchNo = newBatchNo;
    // console.log(b.rounds, b.unitPerRound, b.nextBatchNo, b.totalUnitsBeforeBatch);
  }

  function _appendBatch() private returns (uint64 newBatchNo) {
    uint64 batchNo = _latestBatchNo;
    if (batchNo == 0) {
      newBatchNo = ++_batchCount;
      require(newBatchNo == 1);
      _partial.batchNo = 1;
      _firstOpenBatchNo = 1;
    } else {
      Rounds.Batch memory b = _batches[batchNo];
      if (b.rounds == 0) {
        return batchNo;
      }

      newBatchNo = ++_batchCount;

      _batches[batchNo].nextBatchNo = newBatchNo;
      _batches[newBatchNo].totalUnitsBeforeBatch = b.totalUnitsBeforeBatch + b.unitPerRound * b.rounds;
    }

    _latestBatchNo = newBatchNo;
    return newBatchNo;
  }

  struct GetCoveredDemandParams {
    uint256 loopLimit;
    uint256 receivedCoverage;
    address insured;
    bool done;
  }

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

    uint256 demandLength = demands.length;
    if (demandLength == 0) {
      params.done = true;
      return (coverage, covered, premium);
    }
    if (params.loopLimit == 0) {
      return (coverage, covered, premium);
    }

    covered = _covered[params.insured];
    params.receivedCoverage = covered.coveredUnits;

    (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = (
      premium.coveragePremium,
      premium.coveragePremiumRate,
      premium.lastUpdatedAt
    );

    for (; params.loopLimit > 0; params.loopLimit--) {
      if (
        covered.lastUpdateIndex >= demandLength ||
        !_collectCoveredDemandSlot(demands[covered.lastUpdateIndex], coverage, covered, premium)
      ) {
        params.done = true;
        break;
      }
    }

    _finalizePremium(coverage);
    coverage.totalDemand = uint256(_unitSize) * _insureds[params.insured].demandedUnits;
    coverage.totalCovered += uint256(_unitSize) * covered.coveredUnits;
    params.receivedCoverage = uint256(_unitSize) * (covered.coveredUnits - params.receivedCoverage);
  }

  function internalUpdateCoveredDemand(GetCoveredDemandParams memory params)
    internal
    returns (DemandedCoverage memory coverage)
  {
    (coverage, _covered[params.insured], _premiums[params.insured]) = internalGetCoveredDemand(params);
  }

  function _collectCoveredDemandSlot(
    Rounds.Demand memory d,
    DemandedCoverage memory coverage,
    Rounds.Coverage memory covered,
    Rounds.CoveragePremium memory premium
  ) private view returns (bool) {
    console.log('collect', d.rounds, covered.lastOpenBatchNo, covered.lastUpdateRounds);

    uint24 fullRounds;
    if (covered.lastUpdateRounds > 0) {
      d.rounds -= covered.lastUpdateRounds;
      d.startBatchNo = covered.lastOpenBatchNo;
    }

    Rounds.Batch memory b;
    while (d.rounds > fullRounds) {
      require(d.startBatchNo != 0);
      b = _batches[d.startBatchNo];
      console.log('collectBatch', d.startBatchNo, b.nextBatchNo, b.rounds);

      if (!b.isFull()) break;
      console.log('collectBatch1');
      require(b.rounds > 0);
      fullRounds += b.rounds;

      (premium.coveragePremium, premium.coveragePremiumRate, premium.lastUpdatedAt) = _calcPremium(
        d,
        premium,
        b.rounds,
        0,
        d.premiumRate,
        b.unitPerRound
      );
      d.startBatchNo = b.nextBatchNo;
    }

    covered.coveredUnits += uint64(fullRounds) * d.unitPerRound;
    (coverage.totalPremium, coverage.premiumRate, coverage.premiumUpdatedAt) = (
      premium.coveragePremium,
      premium.coveragePremiumRate,
      premium.lastUpdatedAt
    );

    if (d.rounds == fullRounds) {
      covered.lastUpdateRounds = 0;
      covered.lastOpenBatchNo = 0;
      covered.lastUpdateIndex++;
      return true;
    }

    require(d.rounds > fullRounds);
    require(d.startBatchNo != 0);
    covered.lastUpdateRounds += fullRounds;
    covered.lastOpenBatchNo = d.startBatchNo;

    PartialState memory part = _partial;
    console.log('collectCheck', part.batchNo, covered.lastOpenBatchNo);
    if (part.batchNo == d.startBatchNo) {
      console.log('collectPartial', part.roundNo, part.roundCoverage);
      if (part.roundNo > 0 || part.roundCoverage > 0) {
        covered.coveredUnits += part.roundNo * d.unitPerRound;
        coverage.pendingCovered =
          (uint256(part.roundCoverage) * d.unitPerRound) /
          _batches[d.startBatchNo].unitPerRound;

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

  function _finalizePremium(DemandedCoverage memory coverage) private view {
    coverage.premiumRate = uint256(_unitSize).wadMul(coverage.premiumRate);
    coverage.totalPremium = uint256(_unitSize).wadMul(coverage.totalPremium);
    //    console.log('calcPremium', premium.lastUpdatedAt, block.timestamp, coverage.premiumRate);
    if (coverage.premiumUpdatedAt != 0) {
      coverage.totalPremium += coverage.premiumRate * (block.timestamp - coverage.premiumUpdatedAt);
      //      console.log('calcPremium', coverage.totalPremium);
    }
  }

  function _calcPremium(
    Rounds.Demand memory d,
    Rounds.CoveragePremium memory premium,
    uint256 rounds,
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
    console.log('premiumBefore', d.startBatchNo, d.unitPerRound, rounds);
    console.log('premiumBefore', mark.timestamp, premium.lastUpdatedAt, mark.duration);
    console.log('premiumBefore', premium.coveragePremium, premium.coveragePremiumRate, pendingCovered);
    console.log('premiumBefore', mark.coverageTW);
    uint256 v = premium.coveragePremium;
    if (premium.lastUpdatedAt != 0) {
      v += uint256(premium.coveragePremiumRate) * ((mark.timestamp - premium.lastUpdatedAt) - mark.duration);
    }

    lastUpdatedAt = mark.timestamp;

    if (mark.coverageTW > 0) {
      // normalization by unitSize to reduce storage requirements
      batchUnitPerRound *= _unitSize;
      v += (premiumRate * d.unitPerRound * mark.coverageTW + (batchUnitPerRound >> 1)) / batchUnitPerRound;
    }
    require(v <= type(uint96).max);
    coveragePremium = uint96(v);

    if (pendingCovered > 0) {
      // normalization by unitSize to reduce storage requirements
      v = pendingCovered + (rounds * d.unitPerRound) * _unitSize;
      v = (v * premiumRate + (_unitSize >> 1)) / _unitSize;
    } else {
      v = premiumRate * (rounds * d.unitPerRound);
    }
    v += premium.coveragePremiumRate;
    require(v <= type(uint64).max);
    coveragePremiumRate = uint64(v);
    console.log('premiumAfter', coveragePremium, coveragePremiumRate);
  }

  function _collectPremiumTotals(
    PartialState memory part,
    Rounds.Batch memory b,
    DemandedCoverage memory coverage
  ) private view {
    Rounds.CoveragePremium memory premium = _poolPremium;

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
      (part.roundCoverage + (b.unitPerRound >> 1)) / b.unitPerRound,
      b.roundPremiumRateSum,
      b.unitPerRound
    );
  }

  function internalGetTotals() internal view returns (DemandedCoverage memory coverage, TotalCoverage memory total) {
    PartialState memory part = _partial;
    if (part.batchNo == 0) return (coverage, total);

    uint64 thisBatch = part.batchNo;

    Rounds.Batch memory b = _batches[thisBatch];
    console.log('batch0', thisBatch, b.nextBatchNo, b.rounds);
    console.log('batch1', part.roundNo);
    _collectPremiumTotals(part, b, coverage);

    coverage.totalCovered = b.totalUnitsBeforeBatch + uint256(part.roundNo) * b.unitPerRound;
    coverage.totalDemand = b.totalUnitsBeforeBatch + uint256(b.rounds) * b.unitPerRound;
    coverage.pendingCovered = part.roundCoverage;
    total.batchCount = 1;

    if (b.isReady()) {
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

      if (b.isReady()) {
        total.usableRounds += b.rounds;
        total.totalCoverable += uint256(b.rounds) * b.unitPerRound;
      }

      if (b.isOpen()) {
        total.openRounds += b.rounds;
      }
    }

    _finalizePremium(coverage);
    coverage.totalCovered *= _unitSize;
    coverage.totalDemand *= _unitSize;
    total.totalCoverable = total.totalCoverable * _unitSize - coverage.pendingCovered;
  }

  struct AddCoverageParams {
    uint64 openBatchNo;
    bool openBatchUpdated;
    bool batchUpdated;
    bool premiumUpdated;
    Rounds.CoveragePremium premium;
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
    if (params.premiumUpdated) {
      _poolPremium = params.premium;
    }
    if (params.openBatchUpdated) {
      _firstOpenBatchNo = params.openBatchNo;
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
      require(b.isReady(), 'wrong partial round'); // sanity check

      _updateTimeMark(part, b.unitPerRound);

      uint256 maxRoundCoverage = uint256(_unitSize) * b.unitPerRound;
      uint256 vacant = maxRoundCoverage - part.roundCoverage;
      if (amount < vacant) {
        part.roundCoverage += uint128(amount);
        return (0, loopLimit - 1, b);
      }
      part.roundCoverage = 0;
      part.roundNo++;
      amount -= vacant;
    } else if (!b.isReady()) {
      if (!internalUseNotReadyBatch(b)) {
        // console.log('partial1', part.batchNo, part.roundNo, part.roundCoverage);
        return (amount, loopLimit - 1, b);
      }
      b.state = Rounds.State.ReadyMin;
      params.batchUpdated = true;
    }
    // TODO optimize time-marking

    params.openBatchNo = _firstOpenBatchNo;
    while (true) {
      loopLimit--;
      require(b.unitPerRound > 0, 'empty round');

      if (part.roundNo >= b.rounds) {
        require(part.roundNo == b.rounds);
        require(part.roundCoverage == 0);

        if (b.state != Rounds.State.Full) {
          b.state = Rounds.State.Full;
          params.batchUpdated = true;

          if (!params.premiumUpdated) {
            params.premium = _poolPremium;
          }
          _updateTotalPremium(part.batchNo, params.premium, b);
          params.premiumUpdated = true;
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

        if (amount == 0) break;

        if (!b.isReady()) {
          if (!internalUseNotReadyBatch(b)) {
            console.log('partial1', part.batchNo, part.roundNo, part.roundCoverage);
            return (amount, loopLimit, b);
          }
          b.state = Rounds.State.ReadyMin;
          params.batchUpdated = true;
        }
      } else {
        _updateTimeMark(part, b.unitPerRound);

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
        if (loopLimit > 0) continue; // make sure to move to the next batch
      }
      if (amount == 0 || loopLimit == 0) {
        break;
      }
    }

    return (amount, loopLimit, b);
  }

  function _updateTotalPremium(
    uint64 batchNo,
    Rounds.CoveragePremium memory premium,
    Rounds.Batch memory b
  ) internal {
    Rounds.Demand memory d;
    d.startBatchNo = batchNo;
    d.unitPerRound = 1;
    uint64 lastRate = premium.coveragePremiumRate;
    (premium.coveragePremium, premium.coveragePremiumRate, premium.lastUpdatedAt) = _calcPremium(
      d,
      premium,
      b.rounds,
      0,
      b.roundPremiumRateSum,
      b.unitPerRound
    );

    if (lastRate != premium.coveragePremiumRate) {
      internalPremiumRateUpdated(premium.coveragePremium, premium.coveragePremiumRate, premium.lastUpdatedAt);
    }
  }

  function internalPremiumRateUpdated(
    uint256 totalPremium,
    uint256 totalRate,
    uint32 updatedAt
  ) internal virtual {}

  function internalUseNotReadyBatch(Rounds.Batch memory) internal virtual returns (bool) {
    return false;
  }

  function _updateTimeMark(PartialState memory part, uint256 batchUnitPerRound) private {
    console.log('==updateTimeMark', part.batchNo);
    require(part.batchNo != 0);
    TimeMark memory mark = _marks[part.batchNo];
    if (mark.timestamp == 0) {
      _marks[part.batchNo] = TimeMark({coverageTW: 0, timestamp: uint32(block.timestamp), duration: 0});
      return;
    }

    uint32 duration = uint32(block.timestamp - mark.timestamp);
    if (duration == 0) return;

    uint256 coverageTW = mark.coverageTW +
      (uint256(_unitSize) * part.roundNo * batchUnitPerRound + part.roundCoverage) *
      duration;
    require(coverageTW <= type(uint192).max);
    mark.coverageTW = uint192(coverageTW);

    mark.duration += duration;
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

  //  function internalCancelCoverageDemand(uint256 unitCount, bool hasMore) external returns (uint256 cancelledUnits) {}

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
