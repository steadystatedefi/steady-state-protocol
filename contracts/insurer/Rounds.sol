// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

/*

UnitPremiumRate per sec * 365 days <= 1 WAD (i.e. 1 WAD = 100% of coverage p.a.)
=>> UnitPremiumRate is uint40
=>> timestamp ~80y

=>> RoundPremiumRate = UnitPremiumRate (40) * unitPerRound (16) = 56

=>> InsuredPremiumRate = UnitPremiumRate (40) * avgUnits (24) = 64
=>> AccumulatedInsuredPremiumRate = InsuredPremiumRate (64) * timestamp (32) = 96

=>> PoolPremiumRate = UnitPremiumRate (40) * maxUnits (64) = 104
=>> PoolAccumulatedPremiumRate = PoolPremiumRate (104) * timestamp (32) = 140

*/

library Rounds {
  /// @dev must be equal to bit size of Demand.premiumRate
  uint8 internal constant DEMAND_RATE_BITS = 40;

  /// @dev demand log entry, related to a single insurd pool
  struct Demand {
    /// @dev first batch that includes this demand
    uint64 startBatchNo;
    /// @dev premiumRate for this demand. See DEMAND_RATE_BITS
    uint40 premiumRate;
    /// @dev number of rounds accross all batches where this demand was added
    uint24 rounds;
    /// @dev number of units added to each round by this demand
    uint16 unitPerRound;
  }

  struct InsuredParams {
    /// @dev a minimum number of units to be allocated for an insured in a single batch. Best effort, but may be ignored.
    uint24 minUnits;
    /// @dev a maximum % of units this insured can have per round. This is a hard limit.
    uint16 maxShare;
    /// @dev a minimum premium rate to accept new coverage demand
    uint40 minPremiumRate;
  }

  struct InsuredEntry {
    /// @dev batch number to add next demand (if it will be open) otherwise it will start with the earliest open batch
    uint64 nextBatchNo;
    /// @dev total number of units demanded by this insured pool
    uint64 demandedUnits;
    /// @dev see InsuredParams
    PackedInsuredParams params;
    /// @dev status of the insured pool
    MemberStatus status;
  }

  struct Coverage {
    /// @dev total number of units covered for this insured pool
    uint64 coveredUnits;
    /// @dev index of Demand entry that is covered partially or will be covered next
    uint64 lastUpdateIndex;
    /// @dev Batch that is a part of the partially covered Demand
    uint64 lastUpdateBatchNo;
    /// @dev number of rounds within the Demand (lastUpdateIndex) starting from Demand's startBatchNo till lastUpdateBatchNo
    uint24 lastUpdateRounds;
    /// @dev number of rounds of a partial batch included into coveredUnits
    uint24 lastPartialRoundNo;
  }

  struct CoveragePremium {
    /// @dev total premium collected till lastUpdatedAt
    uint96 coveragePremium;
    /// @dev premium collection rate at lastUpdatedAt
    uint64 coveragePremiumRate;
    // uint64
    /// @dev time of the last updated applied
    uint32 lastUpdatedAt;
  }

  /// @dev Draft round can NOT receive coverage, more units can be added, always unbalanced
  /// @dev ReadyMin is a Ready round where more units can be added, may be unbalanced
  /// @dev Ready round can receive coverage, more units can NOT be added, balanced
  /// @dev Full round can NOT receive coverage, more units can NOT be added - full rounds are summed up and ignored further
  enum State {
    Draft,
    ReadyMin,
    Ready,
    Full
  }

  struct Batch {
    /// @dev sum of premium rates provided by all units (from different insured pools), per round
    uint56 roundPremiumRateSum;
    /// @dev next batch number (one-way linked list)
    uint64 nextBatchNo;
    /// @dev total number of units befor this batch, this value may not be exact for non-ready batches
    uint80 totalUnitsBeforeBatch;
    /// @dev number of rounds within the batch, can only be zero for an empty (not initialized batch)
    uint24 rounds;
    /// @dev number of units for each round of this batch
    uint16 unitPerRound;
    /// @dev state of this batch
    State state;
  }

  function isFull(Batch memory b) internal pure returns (bool) {
    return isFull(b.state);
  }

  function isOpen(Batch memory b) internal pure returns (bool) {
    return isOpen(b.state);
  }

  function isReady(Batch memory b) internal pure returns (bool) {
    return isReady(b.state);
  }

  function isDraft(State state) internal pure returns (bool) {
    return state == State.Draft;
  }

  function isFull(State state) internal pure returns (bool) {
    return state == State.Full;
  }

  function isOpen(State state) internal pure returns (bool) {
    return state <= State.ReadyMin;
  }

  function isReady(State state) internal pure returns (bool) {
    return state >= State.ReadyMin && state <= State.Ready;
  }

  type PackedInsuredParams is uint80;

  function packInsuredParams(
    uint24 minUnits_,
    uint16 maxShare_,
    uint40 minPremiumRate_
  ) internal pure returns (PackedInsuredParams) {
    return PackedInsuredParams.wrap(uint80((uint256(minPremiumRate_) << 40) | (uint256(maxShare_) << 24) | minUnits_));
  }

  function unpackInsuredParams(PackedInsuredParams v) internal pure returns (InsuredParams memory p) {
    p.minUnits = minUnits(v);
    p.maxShare = maxShare(v);
    p.minPremiumRate = minPremiumRate(v);
  }

  function minUnits(PackedInsuredParams v) internal pure returns (uint24) {
    return uint24(PackedInsuredParams.unwrap(v));
  }

  function maxShare(PackedInsuredParams v) internal pure returns (uint16) {
    return uint16(PackedInsuredParams.unwrap(v) >> 24);
  }

  function minPremiumRate(PackedInsuredParams v) internal pure returns (uint40) {
    return uint40(PackedInsuredParams.unwrap(v) >> 40);
  }
}

enum MemberStatus {
  Unknown,
  JoinCancelled,
  JoinRejected,
  JoinFailed,
  Declined,
  Joining,
  Accepted,
  Banned,
  NotApplicable
}
