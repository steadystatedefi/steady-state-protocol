// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC1363.sol';

interface ITokenDelegate is IERC1363Receiver {
  function delegatedAllowance(address account) external view returns (uint256);
}
