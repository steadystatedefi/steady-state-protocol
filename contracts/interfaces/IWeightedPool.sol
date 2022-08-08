// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IWeightedPoolInit {
  function initializeWeighted(
    address governor,
    string calldata tokenName,
    string calldata tokenSymbol,
    WeightedPoolParams calldata params
  ) external;
}

struct WeightedPoolParams {
  /// @dev a recommended maximum of uncovered units per pool
  uint32 maxAdvanceUnits;
  /// @dev a recommended minimum of units per batch
  uint32 minAdvanceUnits;
  /// @dev a target risk level, an insured with higher risk will get a lower share per batch (and vice versa)
  uint16 riskWeightTarget;
  /// @dev a minimum share per batch per insured, lower values will be replaced by this one
  uint16 minInsuredSharePct;
  /// @dev a maximum share per batch per insured, higher values will be replaced by this one
  uint16 maxInsuredSharePct;
  /// @dev an amount of units per round in a batch to consider the batch as ready to be covered
  uint16 minUnitsPerRound;
  /// @dev an amount of units per round in a batch to consider a batch as full (no more units can be added)
  uint16 maxUnitsPerRound;
  /// @dev an "overcharge" / a maximum allowed amount of units per round in a batch that can be applied to reduce batch fragmentation
  uint16 overUnitsPerRound;
  /// @dev an amount of coverage to be given out on reconciliation, where 100% disables drawdown permanently. A new value must be >= the prev one.
  uint16 coveragePrepayPct;
  /// @dev an amount of coverage usable as collateral drawdown, where 0% stops drawdown. MUST: maxUserDrawdownPct + coveragePrepayPct <= 100%
  uint16 maxUserDrawdownPct;
  /// @dev limits a number of auto-pull loops by amount of added coverage divided by this number, zero disables auto-pull
  uint16 unitsPerAutoPull;
}
