// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IDemandRefiller {
  /// @dev invoked by chartered pools to request more coverage demand
  function pullCoverageDemand() external returns (bool);
}

interface IDemandRefillable {
  function updateRefiller(address, bool hasRefill) external;

  function requestBuyOff(uint256 buyOffIncrement) external;

  function distributeBuyOff(address[] calldata receivers, uint256[] calldata amounts) external;
}
