// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IJoinHandler.sol';

interface IInsurerGovernor is IJoinHandler {
  function governerQueryAccessControlMask(address subject, uint256 filterMask) external view returns (uint256);
}
