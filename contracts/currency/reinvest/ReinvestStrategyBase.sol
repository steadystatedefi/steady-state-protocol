// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IReinvestStrategy.sol';
import '../../tools/SafeERC20.sol';
import '../../tools/Errors.sol';
import './AaveTypes.sol';

abstract contract ReinvestStrategyBase is IReinvestStrategy {
  address private immutable _manager;

  constructor(address manager) {
    Value.require(manager != address(0));
    _manager = manager;
  }

  function _onlyManager() private view {
    Access.require(msg.sender == _manager);
  }

  modifier onlyManager() {
    _onlyManager();
    _;
  }
}
