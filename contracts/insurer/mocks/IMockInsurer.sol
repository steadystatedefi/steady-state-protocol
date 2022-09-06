// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../ImperpetualPoolBase.sol';
import './MockWeightedRounds.sol';

interface IMockInsurer {
  function getTotals(uint256) external view returns (DemandedCoverage memory, TotalCoverage memory);
}
