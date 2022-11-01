// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../insurer/Rounds.sol';

interface IJoinHandler {
  /// @dev Callback from insurer to its contract-based governor to handle a join request.
  /// @return a status to be applied to the joiner.
  function handleJoinRequest(address) external returns (MemberStatus);
}
