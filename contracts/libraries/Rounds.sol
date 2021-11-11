// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/*

UnitPremiumRate per sec * 365 days <= 1 WAD (i.e. 1 WAD = 100% of coverage p.a.)
=>> UnitPremiumRate is uint40
=>> timestamp ~10y

=>> RoundPremiumRate = UnitPremiumRate (40) * unitPerRound (16) = 56

=>> InsuredPremiumRate = UnitPremiumRate (40) * avgUnits (24) = 64
=>> AccumulatedInsuredPremiumRate = InsuredPremiumRate (64) * timestamp (32) = 96

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

  struct InsuredEntry {
    uint64 latestBatchNo;
    uint64 demandedUnits;
    uint24 minUnits;
    uint16 maxShare;
    InsuredStatus status;
  }

  struct Coverage {
    uint64 coveredUnits;
    uint64 lastUpdateIndex;
    uint64 lastOpenBatchNo;
    uint24 lastUpdateRounds;
  }

  struct CoveragePremium {
    uint96 coveragePremium;
    uint64 coveragePremiumRate;
    // uint64
    uint32 lastUpdatedAt;
  }

  /// @dev Draft round can NOT receive coverage, more units can be added, always unbalanced
  /// @dev ReadyMin is a Ready round with some units cancelled, can receive coverage, more units can be added, unbalanced
  /// @dev Ready round can receive coverage, more units can NOT be added, balanced
  /// @dev Full round can NOT receive coverage, more units can NOT be added - full rounds are summed up and ignored further
  enum State {
    Draft,
    ReadyMin,
    Ready,
    Full
  }

  struct Batch {
    uint56 roundPremiumRateSum;
    uint64 nextBatchNo;
    /// @dev totalUnitsBeforeBatch value may be lower for non-ready batches
    uint64 totalUnitsBeforeBatch;
    /// @dev should be divided by unitPerRound to get the average rate
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

  function isReady(Batch memory b) internal pure returns (bool) {
    return b.state >= State.ReadyMin && b.state <= State.Ready;
  }
}

enum InsuredStatus {
  Unknown,
  JoinCancelled,
  JoinRejected,
  JoinFailed,
  Declined,
  Joining,
  Accepted,
  Banned
}
