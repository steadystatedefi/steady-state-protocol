// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IWeightedPoolInit {
  function initializeWeighted(address governor,
    string calldata tokenName,
    string calldata tokenSymbol,
    WeightedPoolParams calldata params) external;
}

struct WeightedPoolParams {
  uint32 maxAdvanceUnits;
  uint32 minAdvanceUnits;
  uint16 riskWeightTarget;
  uint16 minInsuredShare;
  uint16 maxInsuredShare;
  uint16 minUnitsPerRound;
  uint16 maxUnitsPerRound;
  uint16 overUnitsPerRound;
  uint16 coveragePrepayPct; // 100% = no drawdown, this value can ONLY be increased 
  uint16 maxUserDrawdownPct; // 0% = no drawdown, maxUserDrawdownPct + coveragePrepayPct <= 100%
}
