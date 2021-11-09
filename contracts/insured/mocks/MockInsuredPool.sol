// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IInsuredPool.sol';

contract MockInsuredPool is IInsuredPool {
  constructor(address collateral_) {}

  function onTransferReceived(
    address operator,
    address from,
    uint256 value,
    bytes memory data
  ) external override returns (bytes4) {}

  function collateral() external view override returns (address) {}

  function joinProcessed(bool accepted) external override {}

  function pullCoverageDemand() external override returns (bool) {}
}
