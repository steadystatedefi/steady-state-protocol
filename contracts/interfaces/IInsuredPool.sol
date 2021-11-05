// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IInsuredPool {
  /// @dev address of the collateral fund and coverage token ($CC)
  function collateral() external view returns (address);

  /// @dev is called by insurer from or after requestJoin() to inform this insured pool if it was accepted or not
  function joinProcessed(bool accepted) external;

  function pullCoverageDemand() external;
}

interface DInsuredPoolTransfer {
  function addCoverage(
    address account,
    uint256 minAmount,
    uint256 minPremiumRate,
    address insurerPool
  ) external;
}
