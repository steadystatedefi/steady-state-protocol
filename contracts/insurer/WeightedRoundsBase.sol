// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../interfaces/IInsurerPool.sol';
import '../libraries/Rounds.sol';

import 'hardhat/console.sol';

abstract contract WeightedRoundsBase {
  using Rounds for Rounds.Batch;
  using Rounds for Rounds.State;
  using WadRayMath for uint256;

  uint256 private immutable _unitSize;

  constructor(uint256 unitSize) {
    require(unitSize > 0);
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

  function internalSetInsuredStatus(address account, InsuredStatus status) internal {
    _insureds[account].status = status;
  }

  function internalGetInsuredStatus(address account) internal view returns (InsuredStatus) {
    return _insureds[account].status;
  }

  ///@dev Sets the minimum amount of units this insured pool will assign and the max share % of the pool it can take up
  function internalSetInsuredParams(address account, Rounds.InsuredParams memory params) internal {
    Rounds.InsuredEntry memory entry = _insureds[account];
    entry.minUnits = params.minUnits;
    entry.maxShare = params.maxShare;

    _insureds[account] = entry;
  }

  function internalGetInsuredParams(address account)
    internal
    view
    returns (InsuredStatus, Rounds.InsuredParams memory)
  {
    Rounds.InsuredEntry memory entry = _insureds[account];

    return (entry.status, Rounds.InsuredParams({minUnits: entry.minUnits, maxShare: entry.maxShare}));
  }

  function internalUnitSize() internal view returns (uint256) {
    return _unitSize;
  }

  struct AddCoverageDemandParams {
    uint256 loopLimit;
    address insured;
    uint40 premiumRate;
  }

  ///@dev Adds coverage demand by performing the following:
  /// Find which batch to first append to
  /// Fill the batch, and create new batches if needed, looping under either all units added to batch or loopLimit
  //  Return the remaining demanded units
  function internalAddCoverageDemand(uint64 unitCount, AddCoverageDemandParams memory params)
    internal
    returns (
      uint64 // remainingCount
    )
  {
    // console.log('\ninternalAddCoverageDemand');
    Rounds.InsuredEntry memory entry = _insureds[params.insured];
    require(entry.status == InsuredStatus.Accepted);
    if (unitCount == 0 || params.loopLimit == 0) {
      return unitCount;
    }

    Rounds.Demand[] storage demands = _demands[params.insured];

    (Rounds.Batch memory b, uint64 thisBatch, bool isFirstOfOpen) = _findBatchToAppend(entry.nextBatchNo);

    // TODO try to reuse the previous Demand slot from storage
    Rounds.Demand memory demand;

    for (;;) {
      // console.log('addDLoop', nextBatch, isFirstOfOpen, totalUnitsBeforeBatch);
      params.loopLimit--;

      require(thisBatch != 0);
      if (b.rounds == 0) {
        // NB! empty batches can also be produced by cancellation

        uint32 openRounds = _openRounds;
        b.rounds = internalBatchAppend(_adjustedTotalUnits(b.totalUnitsBeforeBatch), openRounds, unitCount);
        if (b.rounds > 0) {
          _openRounds = openRounds + b.rounds;
          _initTimeMark(_latestBatchNo = b.nextBatchNo = ++_batchCount);
        }
      }

      uint16 addPerRound;
      bool takeNext;
      if (b.isOpen()) {
        if (b.rounds > 0) {
          (addPerRound, takeNext) = _addToBatch(unitCount, b, entry, params, isFirstOfOpen);
        }

        if (isFirstOfOpen && b.isOpen()) {
          _firstOpenBatchNo = thisBatch;
          isFirstOfOpen = false;
        }
      }

      if (_addToSlot(demand, demands, addPerRound, b.rounds)) {
        demand.startBatchNo = thisBatch;
        demand.premiumRate = params.premiumRate;
      }

      if (addPerRound > 0) {
        require(takeNext);
        uint64 addedUnits = uint64(addPerRound) * b.rounds;
        unitCount -= addedUnits;
        entry.demandedUnits += addedUnits;
      }

      _batches[thisBatch] = b;

      if (!takeNext) {
        break;
      }

      entry.nextBatchNo = thisBatch = b.nextBatchNo;
      require(thisBatch != 0);

      uint80 totalUnitsBeforeBatch = b.totalUnitsBeforeBatch + uint80(b.unitPerRound) * b.rounds;
      b = _batches[thisBatch];

      if (unitCount == 0 || params.loopLimit == 0) {
        if (b.totalUnitsBeforeBatch != totalUnitsBeforeBatch) {
          b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
          _batches[thisBatch] = b;
        }
        break;
      }

      b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
    }

    _insureds[params.insured] = entry;

    if (demand.unitPerRound != 0) {
      demands.push(demand);
    }

    if (isFirstOfOpen) {
      _firstOpenBatchNo = thisBatch;
    }

    return unitCount;
  }

  /// @dev Finds which batch to add coverage demand to. Attempts to use nextBatchNo if it is accepting coverage demand
  ///   Returns the current batch, its number and whether batches were filled
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
      require(_batchCount == 0);
      require(nextBatchNo == 0);
      _initTimeMark(_latestBatchNo = _batchCount = _partial.batchNo = _firstOpenBatchNo = 1);
      return (b, 1, true);
    }

    if (nextBatchNo != 0 && (b = _batches[nextBatchNo]).isOpen()) {
      thisBatchNo = nextBatchNo;
    } else {
      b = _batches[thisBatchNo = firstOpen];
    }

    if (b.nextBatchNo == 0) {
      require(b.rounds == 0);
    } else {
      PartialState memory part = _partial;
      if (part.batchNo == thisBatchNo) {
        uint24 remainingRounds = part.roundCoverage == 0 ? part.roundNo : part.roundNo + 1;
        if (remainingRounds > 0) {
          _splitBatch(remainingRounds, b);

          if (part.roundCoverage == 0) {
            b.state = Rounds.State.Full;

            Rounds.CoveragePremium memory premium = _poolPremium;
            _updateTotalPremium(thisBatchNo, premium, b);
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

  ///@dev adds the demand to the list of demands
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

    if (demand.unitPerRound != 0) {
      demands.push(demand);
    }
    demand.rounds = batchRounds;
    demand.unitPerRound = addPerRound;
    return true;
  }

  ///@dev Adds units to the batch. Can split the batch when the number of units is less than the number of rounds inside the batch.
  /// The unitCount units are evenly distributed across rounds by increase the # of units per round
  function _addToBatch(
    uint64 unitCount,
    Rounds.Batch memory b,
    Rounds.InsuredEntry memory entry,
    AddCoverageDemandParams memory params,
    bool canClose
  ) private returns (uint16 addPerRound, bool takeNext) {
    require(b.isOpen() && b.rounds > 0); // TODO dev sanity check - remove later

    if (unitCount < b.rounds) {
      // split the batch or return the non-allocated units
      uint24 splitRounds = internalBatchSplit(entry.demandedUnits, entry.minUnits, b.rounds, uint24(unitCount));
      // console.log('post-internalBatchSplit', splitRounds, unitCount);
      if (splitRounds == 0) {
        return (0, false);
      }
      require(unitCount >= splitRounds);
      // console.log('batchSplit-before', splitRounds, b.rounds, b.nextBatchNo);
      _splitBatch(splitRounds, b);
      // console.log('batchSplit-after', b.rounds, b.nextBatchNo);
    }

    (uint16 maxShareUnitsPerRound, uint16 minUnitsPerRound, uint16 maxUnitsPerRound) = internalRoundLimits(
      _adjustedTotalUnits(b.totalUnitsBeforeBatch),
      b.rounds,
      b.unitPerRound,
      entry.demandedUnits,
      entry.maxShare
    );

    if (maxShareUnitsPerRound > 0 && b.unitPerRound < maxUnitsPerRound) {
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
    }

    if (b.unitPerRound >= minUnitsPerRound) {
      b.state = canClose && b.unitPerRound >= maxUnitsPerRound ? Rounds.State.Ready : Rounds.State.ReadyMin;
    }
    return (addPerRound, true);
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

  ///@dev Reduces the current batch's rounds to remainingRounds and adds the leftover rounds to a new batch.
  /// Also checks if this is the new latest batch
  function _splitBatch(uint24 remainingRounds, Rounds.Batch memory b) private {
    if (b.rounds == remainingRounds) return;
    require(b.rounds > remainingRounds, 'split beyond size');

    uint64 newBatchNo = ++_batchCount;
    // // console.log(b.rounds, b.unitPerRound, b.nextBatchNo, b.totalUnitsBeforeBatch);

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
    // // console.log(b.rounds, b.unitPerRound, b.nextBatchNo, b.totalUnitsBeforeBatch);
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
    address insured;
    bool done;
  }

  ///@dev Get the amount of demand that has been covered and the premium earned from it
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

    _finalizePremium(coverage, true);
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

  ///@dev Sets the function parameters to their correct values by:
  /// - Setting d.startBatchNo to the first open batch and calculating # of full rounds and premium accrued from full batches
  /// - Set covered to the premium values from the newly counted full batches
  /// - RETURN true if the demand has been completely filled
  /// - Updated with partional round info for number of covered units and the premium earned on them
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
      require(d.startBatchNo != 0);
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

    require(d.rounds > fullRounds);
    require(d.startBatchNo != 0);
    covered.lastUpdateRounds += fullRounds;
    covered.lastUpdateBatchNo = d.startBatchNo;

    PartialState memory part = _partial;
    // console.log('collectCheck', part.batchNo, covered.lastUpdateBatchNo);
    if (part.batchNo == d.startBatchNo) {
      // console.log('collectPartial', part.roundNo, part.roundCoverage);
      if (part.roundNo > 0 || part.roundCoverage > 0) {
        covered.coveredUnits += uint64(covered.lastPartialRoundNo = part.roundNo) * d.unitPerRound;
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

  ///@dev Calculate the actual premium values since variables keep track of number of coverage units instead of
  /// amount of coverage currency
  function _finalizePremium(DemandedCoverage memory coverage, bool roundUp) private view {
    coverage.premiumRate = roundUp
      ? uint256(_unitSize).wadMulUp(coverage.premiumRate)
      : uint256(_unitSize).wadMul(coverage.premiumRate);
    coverage.totalPremium = uint256(_unitSize).wadMul(coverage.totalPremium);
    //    // console.log('calcPremium', premium.lastUpdatedAt, block.timestamp, coverage.premiumRate);
    if (coverage.premiumUpdatedAt != 0) {
      coverage.totalPremium += coverage.premiumRate * (block.timestamp - coverage.premiumUpdatedAt);
      //      // console.log('calcPremium', coverage.totalPremium);
    }
  }

  ///@dev Calculate the new premium values by including the rounds that have been filled for demand d and
  /// the partial rounds
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
      batchUnitPerRound *= _unitSize;
      v += (premiumRate * d.unitPerRound * mark.coverageTW + (batchUnitPerRound - 1)) / batchUnitPerRound;
    }
    require(v <= type(uint96).max);
    coveragePremium = uint96(v);

    if (pendingCovered > 0) {
      // normalization by unitSize to reduce storage requirements
      v = pendingCovered + (rounds * d.unitPerRound) * _unitSize;
      v = (v * premiumRate + (_unitSize - 1)) / _unitSize;
    } else {
      v = premiumRate * (rounds * d.unitPerRound);
    }
    v += premium.coveragePremiumRate;
    require(v <= type(uint64).max);
    coveragePremiumRate = uint64(v);
    // console.log('premiumAfter', coveragePremium, coveragePremiumRate);
  }

  ///@dev Update the premium totals of coverage by including batch b
  function _collectPremiumTotals(
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

  function internalGetPremiumTotals() internal view returns (DemandedCoverage memory coverage) {
    PartialState memory part = _partial;
    if (part.batchNo != 0) {
      return internalGetPremiumTotals(part, _batches[part.batchNo], _poolPremium);
    }
  }

  function internalGetPremiumTotals(
    PartialState memory part,
    Rounds.Batch memory b,
    Rounds.CoveragePremium memory premium
  ) internal view returns (DemandedCoverage memory coverage) {
    _collectPremiumTotals(part, b, premium, coverage);

    coverage.totalCovered = _adjustedTotalUnits(b.totalUnitsBeforeBatch) + uint256(part.roundNo) * b.unitPerRound;
    coverage.pendingCovered = part.roundCoverage;

    _finalizePremium(coverage, false);
    coverage.totalCovered *= _unitSize;
  }

  ///@dev Get the Pool's total amount of coverage that has been demanded, covered and allocated (partial round) and
  /// the corresponding premium based on these values
  function internalGetTotals(uint256 loopLimit)
    internal
    view
    returns (DemandedCoverage memory coverage, TotalCoverage memory total)
  {
    PartialState memory part = _partial;
    if (part.batchNo == 0) return (coverage, total);

    uint64 thisBatch = part.batchNo;

    Rounds.Batch memory b = _batches[thisBatch];
    // console.log('batch0', thisBatch, b.nextBatchNo, b.rounds);
    // console.log('batch1', part.roundNo);
    _collectPremiumTotals(part, b, _poolPremium, coverage);

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
    uint64 openBatchNo;
    bool openBatchUpdated;
    bool batchUpdated;
    bool premiumUpdated;
    Rounds.CoveragePremium premium;
  }

  function internalAddCoverage(uint256 amount, uint256 loopLimit)
    internal
    returns (
      uint256 remainingAmount,
      uint256 remainingLoopLimit,
      AddCoverageParams memory params,
      PartialState memory part,
      Rounds.Batch memory b
    )
  {
    part = _partial;

    if (amount == 0 || loopLimit == 0 || part.batchNo == 0) {
      return (amount, loopLimit, params, part, b);
    }

    (amount, loopLimit, b) = _addCoverage(amount, loopLimit, part, params);
    if (params.batchUpdated) {
      _batches[part.batchNo] = b;
    }
    if (params.premiumUpdated) {
      _poolPremium = params.premium;
    }
    if (params.openBatchUpdated) {
      require(params.openBatchNo != 0);
      _firstOpenBatchNo = params.openBatchNo;
    }
    _partial = part;
    // console.log('partial3', part.batchNo, part.roundNo, part.roundCoverage);
    return (amount, loopLimit, params, part, b);
  }

  ///@dev Adds coverage to the pool and stops if there are no batches left to add coverage to
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
      return (amount, loopLimit - 1, b);
    }
    // TODO optimize time-marking

    params.openBatchNo = _firstOpenBatchNo;
    while (true) {
      loopLimit--;

      // if filled in the final round of a batch
      if (part.roundNo >= b.rounds) {
        require(part.roundNo == b.rounds);
        require(part.roundCoverage == 0);

        if (b.state != Rounds.State.Full) {
          b.state = Rounds.State.Full;
          params.batchUpdated = true;

          if (b.unitPerRound == 0) {
            // this is a special case when all units were removed by cancellations
            require(b.rounds == 0);
            // total premium doesn't need to be updated as the rate remains the same
          } else {
            if (!params.premiumUpdated) {
              params.premium = _poolPremium;
            }
            _updateTotalPremium(part.batchNo, params.premium, b);
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

  ///@dev Updates the timeMark for this batch which calculates the "area under the curve" of the coverage curve
  /// over time
  function _updateTimeMark(PartialState memory part, uint256 batchUnitPerRound) private {
    // console.log('==updateTimeMark', part.batchNo);
    require(part.batchNo != 0);
    TimeMark memory mark = _marks[part.batchNo];
    if (mark.timestamp <= 1) {
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

  function internalCanAddCoverage() internal view returns (bool) {
    PartialState memory part = _partial; // TODO check if using storage is better for gas
    return part.batchNo != 0 && (part.roundCoverage > 0 || _batches[part.batchNo].state.isReady());
  }

  struct CancelCoverageDemandParams {
    uint256 loopLimit;
    address insured;
    bool done;
    // temp var
    uint80 totalUnitsBeforeBatch;
  }

  function internalCancelCoverageDemand(uint64 unitCount, CancelCoverageDemandParams memory params)
    internal
    returns (uint64)
  {
    // TODO problems: consider zero-round batches when adding demand and coverage

    Rounds.InsuredEntry storage entry = _insureds[params.insured];
    require(entry.status == InsuredStatus.Accepted);

    if (unitCount == 0 || params.loopLimit == 0 || entry.demandedUnits == _covered[params.insured].coveredUnits) {
      return 0;
    }

    Rounds.Demand[] storage demands = _demands[params.insured];

    (
      uint256 index,
      uint64 batchNo,
      uint256 skippedRounds,
      Rounds.Demand memory demand,
      uint64 cancelledUnits
    ) = _findAndAdjustUncovered(unitCount, demands, params);

    if (cancelledUnits == 0) {
      return 0;
    }

    entry.nextBatchNo = batchNo;
    entry.demandedUnits -= cancelledUnits;

    uint24 cancelFirstSlotRounds = uint24(demand.rounds - skippedRounds);
    require(cancelFirstSlotRounds > 0);

    demand.rounds = uint24(skippedRounds);

    (batchNo, params.totalUnitsBeforeBatch) = _adjustUncoveredBatches(
      batchNo,
      cancelFirstSlotRounds,
      _batches[batchNo].totalUnitsBeforeBatch,
      demand
    );

    _adjustUncoveredSlots(batchNo, uint80(cancelFirstSlotRounds) * demand.unitPerRound, demands, index + 1, params);

    for (uint256 i = demands.length - index; i > 1; i--) {
      demands.pop();
    }

    if (demand.rounds == 0) {
      demands.pop();
    } else {
      demands[index] = demand;
    }

    return cancelledUnits;
  }

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

    for (index = demands.length; index > 0 && params.loopLimit > 0; params.loopLimit--) {
      index--;

      Rounds.Demand memory prev = demand;
      demand = demands[index];

      uint64 cancelUnits;
      (params.done, batchNo, cancelUnits, skippedRounds) = _findUncoveredBatch(
        part,
        demand,
        unitCount - cancelledUnits
      );

      cancelledUnits += cancelUnits;
      if (params.done) {
        if (skippedRounds == demand.rounds) {
          // the whole demand slot was skipped, so use the previous one
          require(cancelUnits == 0);
          index++;
          demand = prev;
          batchNo = prev.startBatchNo;
          skippedRounds = 0;
        }
        break;
      }

      require(skippedRounds == 0);
    }
  }

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
          require(skippedRounds == demand.rounds);
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
      (batchNo, params.totalUnitsBeforeBatch) = _adjustUncoveredBatches(
        d.startBatchNo,
        d.rounds,
        params.totalUnitsBeforeBatch,
        d
      );
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

  function _adjustTotalUnits(
    uint64 batchNo,
    uint64 untilBatchNo,
    uint80 totalUnitsBeforeBatch
  ) private returns (uint64, uint80) {
    for (; batchNo > 0 && batchNo != untilBatchNo; ) {
      Rounds.Batch storage batch = _batches[batchNo];
      batch.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
      totalUnitsBeforeBatch += uint80(batch.rounds) * batch.unitPerRound;
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
    return (
      uint256(b.totalUnitsBeforeBatch) + _partial.roundNo * b.unitPerRound,
      _pendingCancelledCoverageUnits,
      _pendingCancelledDemandUnits
    );
  }

  function internalApplyAdjustmentsToTotals() internal {
    uint80 totals = _pendingCancelledCoverageUnits;
    if (totals == 0 && _pendingCancelledDemandUnits == 0) {
      return;
    }
    (_pendingCancelledCoverageUnits, _pendingCancelledDemandUnits) = (0, 0);

    uint64 batchNo = _partial.batchNo;
    totals = _batches[batchNo].totalUnitsBeforeBatch - totals;
    batchNo = _batches[batchNo].nextBatchNo;

    for (; batchNo > 0; ) {
      Rounds.Batch storage b = _batches[batchNo];
      if (b.totalUnitsBeforeBatch != totals) {
        b.totalUnitsBeforeBatch = totals;
      }
      totals += uint80(b.rounds) * b.unitPerRound;
      batchNo = b.nextBatchNo;
    }
  }

  function internalCancelCoverage(address insured)
    internal
    returns (
      DemandedCoverage memory coverage,
      uint256 excessCoverage,
      uint256 providedCoverage,
      uint256 receivedCoverage
    )
  {
    Rounds.InsuredEntry storage entry = _insureds[insured];
    if (entry.demandedUnits == 0) {
      return (coverage, 0, 0, 0);
    }

    Rounds.Coverage memory covered;
    (coverage, covered, receivedCoverage) = _syncBeforeCancelCoverage(insured);

    Rounds.Demand[] storage demands = _demands[insured];
    Rounds.Demand memory d;
    PartialState memory part = _partial;

    if (covered.lastUpdateIndex < demands.length) {
      require(
          covered.lastUpdateIndex == demands.length - 1 && 
          covered.lastUpdateBatchNo == part.batchNo && 
          covered.lastPartialRoundNo == part.roundNo, 
          'demand must be cancelled');

      d = demands[covered.lastUpdateIndex];
    } else {
      require(entry.demandedUnits == covered.coveredUnits);
    }

    providedCoverage = covered.coveredUnits * _unitSize;

    if (part.batchNo > 0) {
      excessCoverage = _cancelCovered(insured, part, d);
    }
    _pendingCancelledCoverageUnits += covered.coveredUnits - uint64(covered.lastPartialRoundNo) * d.unitPerRound;

    entry.demandedUnits = 0;
    entry.nextBatchNo = 0;
    delete (_covered[insured]);
    delete (_demands[insured]);
  }

  function _syncBeforeCancelCoverage(address insured) private 
  returns(DemandedCoverage memory coverage, Rounds.Coverage memory covered, uint256 receivedCoverage) {
    GetCoveredDemandParams memory params;
    params.insured = insured;
    params.loopLimit = ~uint256(0);

    (coverage, covered, _premiums[insured]) = internalGetCoveredDemand(params);
    require(params.done);

    receivedCoverage = params.receivedCoverage;
  }

  function _cancelCovered(
    address insured,
    PartialState memory part,
    Rounds.Demand memory d
  ) internal returns (uint128 excessCoverage) {
    Rounds.Batch storage partBatch = _batches[part.batchNo];
    Rounds.Batch memory b = partBatch;

    _cancelPremium(insured, part, b);

    if (d.unitPerRound > 0) {
      (partBatch.unitPerRound, partBatch.roundPremiumRateSum) = 
        (b.unitPerRound -= d.unitPerRound, b.roundPremiumRateSum - uint56(d.premiumRate) * d.unitPerRound);

      if (part.roundCoverage > 0) {
        excessCoverage = uint128(_unitSize) * b.unitPerRound;
        if (part.roundCoverage > excessCoverage) {
          (part.roundCoverage, excessCoverage) = (excessCoverage, part.roundCoverage - excessCoverage);
          _partial.roundCoverage = part.roundCoverage;
        }
      }
    }
  }

  function _cancelPremium(
    address insured,
    PartialState memory part,
    Rounds.Batch memory partBatch
  ) internal {
    Rounds.CoveragePremium memory poolPremium = _poolPremium;
    Rounds.CoveragePremium memory premium = _premiums[insured];

    _updateTimeMark(part, partBatch.unitPerRound);
    _updateTotalPremium(part.batchNo, poolPremium, partBatch);

    // TODO store coveragePremium of cancelled coverages in a separate field

    // poolPremium.coveragePremium -=
    //   premium.coveragePremium +
    //   uint96(premium.coveragePremiumRate) *
    //   (poolPremium.lastUpdatedAt - premium.lastUpdatedAt);

    poolPremium.coveragePremiumRate -= premium.coveragePremiumRate;
    _premiums[insured].coveragePremiumRate = 0;
    _poolPremium = poolPremium;
  }
}
