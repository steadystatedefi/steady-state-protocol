// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/tokens/IERC20.sol';
import '../../tools/Errors.sol';

abstract contract ERC20NoTransferBase is IERC20 {
  function transfer(address, uint256) public pure override returns (bool) {
    revert Errors.NotSupported();
  }

  function allowance(address, address) public pure override returns (uint256) {}

  function approve(address, uint256) public pure override returns (bool) {
    revert Errors.NotSupported();
  }

  function transferFrom(
    address,
    address,
    uint256
  ) public pure override returns (bool) {
    revert Errors.NotSupported();
  }
}
