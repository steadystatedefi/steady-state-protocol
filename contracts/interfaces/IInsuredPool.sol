// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IInsurancePool.sol';

interface IInsuredPool is IInsurancePool {
  /// @dev is called by insurer from or after requestJoin() to inform this insured pool if it was accepted or not
  function joinProcessed(bool accepted) external;

  /// @dev invoked by chartered pools to request more coverage demand
  function pullCoverageDemand() external returns (bool);

  function insuredParams() external returns (InsuredParams memory);

  function offerCoverage(uint256 offeredAmount) external returns (uint256 acceptedAmount, uint256 rate);
}

struct InsuredParams {
  uint24 minUnitsPerInsurer;
  uint16 riskWeightPct;
}

interface DInsuredPoolTransfer {
  function addCoverageByInvestor(
    address account,
    uint256 minAmount,
    uint256 minPremiumRate,
    address insurerPool
  ) external;
}

interface IInsuredEvents {
  event TransferToHold(address indexed from, address indexed to, uint256 value);
  event TransferFromHold(address indexed from, address indexed to, uint256 value);
}
