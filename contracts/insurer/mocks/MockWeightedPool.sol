// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../WeightedPoolBase.sol';

contract MockWeightedPool is WeightedPoolBase {
  constructor(address collateral_, uint256 unitSize) WeightedRoundsBase(unitSize) InsurerPoolBase(collateral_) {}

  // function onTransferReceived(
  //   address operator,
  //   address from,
  //   uint256 value,
  //   bytes memory data
  // ) external override returns (bytes4) {}

  // function requestJoin(address insured) external override {}

  function balanceOf(address account) external view override returns (uint256) {}

  function totalSupply() external view override returns (uint256) {}

  function interestRate(address account) external view override returns (uint256 rate, uint256 accumulatedRate) {}

  function exchangeRate() external view override returns (uint256 rate, uint256 accumulatedRate) {}
}
