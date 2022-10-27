// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICharterable.sol';
import '../insurer/Rounds.sol';

interface IJoinableBase {
  /// @dev Requests evaluation of the `insured` by this insurer. May involve governance and not be completed by return from this call.
  /// @dev IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external;

  /// @dev Cancels request initiated by requestJoin(). Will not revert.
  /// @return membership status of the caller. status
  function cancelJoin() external returns (MemberStatus);
}

interface IJoinable is ICharterable, IJoinableBase {}

interface IJoinEvents {
  event JoinRequested(address indexed insured);
  event JoinCancelled(address indexed insured);
  event JoinProcessed(address indexed insured, bool accepted);
  event JoinRejectionFailed(address indexed insured, bool isPanic, bytes reason);
  event MemberLeft(address indexed insured);
}
