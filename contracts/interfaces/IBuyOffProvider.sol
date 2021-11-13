// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IBuyOffProvider {
  function buyOffBalance()
    external
    view
    returns (
      uint256 requested,
      uint256 collected,
      uint16 buyOffShare
    );

  function requestBuyOff(uint256 buyOffIncrement) external;

  function distributeBuyOff(address[] calldata receivers, uint256[] calldata amounts) external;
}
