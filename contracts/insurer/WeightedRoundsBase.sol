// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../interfaces/IInsurerPool.sol';

library Rounds {
  struct Demand {
    uint80 premiumRate;
    uint64 startBatchNo;
    uint24 rounds;
    uint16 unitPerRound;
  }

  struct InsuredEntry {
    uint64 demandedUnits;
    uint64 earliestBatchNo;
    uint64 latestBatchNo;
    uint32 maxShare;
    uint32 minUnits;
    //    bool hasMore;
  }

  struct Coverage {
    uint128 coveredPremium;
    uint64 coveredUnits;
    uint64 demandIndex;
    uint24 demandRounds;
  }

  enum State {
    Draft,
    ReadyCut,
    Ready,
    Partial,
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
    uint128 premiumRateSum;
  }

  function isFull(State s) internal pure returns (bool) {
    return s == State.Full;
  }

  function isPartial(State s) internal pure returns (bool) {
    return s == State.Partial;
  }

  function isOpen(State s) internal pure returns (bool) {
    return s <= State.ReadyCut;
  }
}

abstract contract WeightedRoundsBase {
  using Rounds for Rounds.State;
  uint256 private _unitSize; // must not change

  mapping(address => Rounds.InsuredEntry) private _insureds;
  mapping(address => Rounds.Demand[]) private _demands;
  mapping(address => Rounds.Coverage) private _covered;

  /// @dev Draft round can NOT receive coverage, more units can be added, always unbalanced
  /// @dev Ready round can receive coverage, more units can NOT be added, balanced
  /// @dev ReadyCut is a Ready round with some units cancelled, can receive coverage, more units can be added, unbalanced
  /// @dev Partial round (exclusive state) receives coverage, more units can NOT be added
  /// @dev Full round can NOT receive coverage, more units can NOT be added - full rounds are summed up and ignored further

  mapping(uint256 => Rounds.Batch) private _batches;
  uint64 private _batchCount;
  uint64 private _latestBatch;
  uint64 private _firstOpenBatch; // less than maxStrikeSize
  // collectedRisk, collectedUnits, risk distribution?

  struct PartialState {
    uint64 batchNo;
    uint24 roundNo;
    uint128 roundCoverage;
  }
  PartialState private _partial;
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
    uint80 premiumRate,
    bool hasMore
  ) internal returns (uint64 residualCount) {
    Rounds.InsuredEntry storage entry = _onlyAcceptedInsured(insured);
    Rounds.Demand[] storage demands = _demands[insured];
    hasMore;
    //    entry.hasMore = hasMore;
    if (unitCount == 0) {
      return 0;
    }

    // internalCheckPremium(insured, batches[i].premiumRate);
    //    uint maxPerRound = internal

    uint64 nextBatch;
    {
      uint64 openBatchNo = _firstOpenBatch;
      if (
        entry.latestBatchNo == 0 || openBatchNo == entry.latestBatchNo || !_batches[entry.latestBatchNo].state.isOpen()
      ) {
        if (openBatchNo != 0) {
          if (_partial.batchNo == openBatchNo && _partial.roundCoverage > 0) {
            nextBatch = _splitBatch(openBatchNo, _partial.roundNo + 1);
          } else {
            nextBatch = openBatchNo;
          }
          // } else {
          //   // attach new batch
          //   nextBatch = 0;
        }
      } else {
        nextBatch = _batches[entry.latestBatchNo].nextBatchNo;
      }
    }

    Rounds.Demand memory demand;
    uint64 totalUnitsBeforeBatch;

    for (; unitCount > 0; ) {
      uint64 thisBatch = nextBatch;
      if (nextBatch == 0) {
        thisBatch = _appendBatch();
      }
      if (entry.earliestBatchNo == 0) {
        entry.earliestBatchNo = thisBatch;
      }

      Rounds.Batch storage b = _batches[thisBatch];
      require(b.state.isOpen()); // TODO dev sanity check - remove later
      nextBatch = b.nextBatchNo;
      {
        uint64 before = b.totalUnitsBeforeBatch;
        if (before >= totalUnitsBeforeBatch) {
          totalUnitsBeforeBatch = before;
        } else {
          b.totalUnitsBeforeBatch = totalUnitsBeforeBatch;
        }
      }

      (uint16 maxAddUnitsPerRound, uint16 maxUnitsPerRound) = internalRoundLimits(
        totalUnitsBeforeBatch,
        entry.demandedUnits,
        entry.maxShare
      );
      uint16 addPerRound;
      uint24 roundsPerBatch = b.rounds;

      if (b.unitPerRound < maxUnitsPerRound) {
        if (roundsPerBatch > 0 && unitCount >= roundsPerBatch) {
          if (unitCount < uint64(roundsPerBatch) << 1) {
            addPerRound = 1;
          } else {
            addPerRound = maxUnitsPerRound - b.unitPerRound;
            if (addPerRound > maxAddUnitsPerRound) {
              addPerRound = maxAddUnitsPerRound;
            }
            uint64 n = unitCount / roundsPerBatch;
            if (n < addPerRound) {
              addPerRound = uint16(n);
            }
          }
        }
        /* if (roundsPerBatch == 0 || unitCount < roundsPerBatch) */
        else {
          // split the batch or return the non-allocated units
          uint24 splitRounds = internalBatchSplit(
            roundsPerBatch,
            entry.demandedUnits,
            uint24(unitCount),
            entry.minUnits
          );
          if (splitRounds == 0) {
            // don't split, return the unused units;
            break;
          }
          require(splitRounds <= unitCount);
          _splitBatch(thisBatch, splitRounds);
        }

        b.unitPerRound += addPerRound;
        b.premiumRateSum += premiumRate * addPerRound;

        {
          uint64 unitsPerBatch = uint64(addPerRound) * roundsPerBatch;
          entry.demandedUnits += unitsPerBatch;
          unitCount -= unitsPerBatch;
        }
      }

      if (addPerRound == 0 || b.unitPerRound >= maxUnitsPerRound) {
        b.state = Rounds.State.Ready;
        // if (_firstOpenBatch == thisBatch)
        // TODO
      }

      totalUnitsBeforeBatch += b.unitPerRound * b.rounds;

      if (demand.unitPerRound == addPerRound) {
        demand.rounds += roundsPerBatch;
      } else {
        if (demand.startBatchNo != 0) {
          demands.push(demand);
        }
        demand = Rounds.Demand({
          startBatchNo: thisBatch,
          rounds: roundsPerBatch,
          unitPerRound: addPerRound,
          premiumRate: premiumRate
        });
      }

      entry.latestBatchNo = thisBatch;
    }

    if (demand.startBatchNo != 0) {
      demands.push(demand);
    }

    return unitCount;
  }

  function internalRoundLimits(
    uint64 totalUnitsBeforeBatch,
    uint64 demandedUnits,
    uint256 maxShare
  ) internal virtual returns (uint16 maxAddUnitsPerRound, uint16 maxUnitsPerRound) {
    totalUnitsBeforeBatch;
    demandedUnits;
    maxShare;
    return (1, 10);
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
    require(remainingRounds > 0);
    Rounds.Batch memory b = _batches[batchNo];
    if (b.rounds == remainingRounds) {
      return b.nextBatchNo;
    }

    newBatchNo = ++_batchCount;

    _batches[batchNo].rounds = remainingRounds;
    _batches[batchNo].nextBatchNo = newBatchNo;

    b.rounds -= remainingRounds;
    b.totalUnitsBeforeBatch += remainingRounds * b.unitPerRound;
    _batches[newBatchNo] = b;
    return newBatchNo;
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

  // function internalCheckPremium(address insured, uint256 premium) private {}

  function cancelCoverageDemand(uint256 unitCount, bool hasMore) external returns (uint256 cancelledUnits) {}

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

    uint256 unitSize = _unitSize;
    for (; covered.demandIndex < demands.length; covered.demandIndex++) {
      Rounds.Demand memory d = demands[covered.demandIndex];
      if (covered.demandRounds > 0) {
        d.rounds -= covered.demandRounds;
        covered.demandRounds = 0;
      }

      while (d.rounds > 0 && d.startBatchNo > 0) {
        Rounds.Batch memory b = _batches[d.startBatchNo];

        if (b.state.isFull()) {
          d.rounds -= b.rounds;
          d.startBatchNo = b.nextBatchNo;
          covered.coveredUnits = b.rounds * d.unitPerRound;
          continue;
        }

        if (b.state.isPartial()) {
          coverage.totalCovered =
            (uint256(unitSize) * _partial.roundNo) *
            d.unitPerRound +
            (uint256(_partial.roundCoverage) * d.unitPerRound) /
            b.unitPerRound;
        }
        break;
      }
    }

    coverage.totalDemand = uint256(entry.demandedUnits) * unitSize;
    coverage.totalCovered += uint256(covered.coveredUnits) * unitSize;
    receivedCoverage = (covered.coveredUnits - receivedCoverage) * unitSize;

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
    return (receivedCoverage, coverage);
  }
}
