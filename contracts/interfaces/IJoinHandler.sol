// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../libraries/Rounds.sol';

interface IJoinHandler {
  function handleJoinRequest(address) external returns (InsuredStatus);
}
