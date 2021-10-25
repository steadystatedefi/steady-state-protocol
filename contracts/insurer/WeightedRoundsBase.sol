// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../interfaces/IInsurerPool.sol';

abstract contract WeightedRoundsBase {
  uint256 private _unitSize;
  uint256 private _maxStrikeSize; // can be increased, but not? decreased

  struct DemandEntry {
    uint256 unitCount;
    uint256 premium;
    uint256 unitPerStrike;
  }

  struct InsuredEntry {
    uint256 coveredUnits;
    uint256 demandedUnits;
    uint256 coveredPremium;
    uint256 earliestRound;
    uint256 latestRound;
    uint256 demandIndex;
  }

  mapping(address => InsuredEntry) private _insureds;
  mapping(address => DemandEntry[]) private _demands;

  struct Round {
    uint256 nextRoundNo;
    uint256 strikes;
    uint256 unitPerStrike;
    uint256 premiumRate;
    bool full;
    bool usable;
  }

  mapping(uint256 => Round) private _rounds;
  uint256 private _lastRound;
  uint256 private _earliestOpenRound; // less than maxStrikeSize
  // collectedRisk, collectedUnits, risk distribution?

  struct PartialState {
    uint256 roundNo;
    uint256 strikeNo;
    uint256 strikeCoverage;
  }
  PartialState private _partialRoundState;

  function coverageUnitSize() external view returns (uint256) {
    return _unitSize;
  }

  function _onlyAcceptedInsured() private view returns (InsuredEntry storage entry) {
    entry = _insureds[msg.sender];
    //    require(entry.status == InsuredStatus.Accepted);
  }

  function addCoverageDemand(CoverageUnitBatch[] calldata batches) external {
    InsuredEntry storage entry = _onlyAcceptedInsured();
    address insured = msg.sender;
    DemandEntry[] storage demands = _demands[insured];

    if (batches.length == 1) {
      _addCoverageDemand(demands, entry, 0, batches[0]);
      return;
    }

    uint256 prevRound;
    CoverageUnitBatch memory lastBatch;

    for (uint256 i = 0; i < batches.length; i++) {
      if (lastBatch.unitCount > 0) {
        if (lastBatch.premiumRate == batches[i].premiumRate) {
          // merge batches
          lastBatch.unitCount += batches[i].unitCount;
          continue;
        }
        prevRound = _addCoverageDemand(demands, entry, prevRound, lastBatch);
      }
      internalCheckPremium(insured, batches[i].premiumRate);
      lastBatch = batches[i];
    }

    if (lastBatch.unitCount > 0) {
      _addCoverageDemand(demands, entry, prevRound, lastBatch);
    }
  }

  function _addCoverageDemand(
    DemandEntry[] storage demands,
    InsuredEntry storage entry,
    uint256 prevRound,
    CoverageUnitBatch memory batch
  ) private returns (uint256) {
    require(batch.unitCount > 0);
    uint256 nextRound;

    if (prevRound == 0) {
      uint256 partialRoundNo = _partialRoundState.roundNo;

      if (entry.latestRound == 0 || _rounds[entry.latestRound].full || partialRoundNo == entry.latestRound) {
        if (partialRoundNo != 0) {
          // break up the partial round when there are more strikes to go
          // ...

          nextRound = _rounds[partialRoundNo].nextRoundNo;
        }
      }
    } else {
      nextRound = _rounds[prevRound].nextRoundNo;
    }

    entry.demandedUnits += batch.unitCount;
    uint256 unitPerStrike = 1;

    for (; batch.unitCount > 0; ) {
      if (nextRound == 0) {
        // create a new round
        nextRound = ++_lastRound;

        _rounds[nextRound] = Round({
          nextRoundNo: 0,
          strikes: batch.unitCount / unitPerStrike, // TODO handle un-even numbers when unitPerStrike > 1
          unitPerStrike: unitPerStrike,
          premiumRate: batch.premiumRate,
          usable: false,
          full: false
        });
        if (prevRound == 0) {
          _partialRoundState.roundNo = nextRound;
        } else {
          _rounds[prevRound].nextRoundNo = nextRound;
        }

        demands.push(DemandEntry(batch.unitCount, batch.premiumRate, unitPerStrike));
        break;
      }
    }

    return nextRound;
  }

  function internalCheckPremium(address insured, uint256 premium) private {}

  function cancelCoverageDemand(uint256 unitCount) external returns (uint256 cancelledUnits) {}

  function getCoverageDemand(address insured) external view returns (DemandedCoverage memory) {}

  function receiveDemandedCoverage(address insured)
    external
    returns (uint256 receivedCoverage, DemandedCoverage memory)
  {}
}
