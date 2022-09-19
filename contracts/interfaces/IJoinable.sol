// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICharterable.sol';

interface IJoinableBase {
  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external;

  // function statusOf(address insured)
}

interface IJoinable is ICharterable, IJoinableBase {}

interface IJoinEvents {
  event JoinRequested(address indexed insured);
  event JoinCancelled(address indexed insured);
  event JoinProcessed(address indexed insured, bool accepted);
  event JoinRejectionFailed(address indexed insured, bool isPanic, bytes reason);
  event MemberLeft(address indexed insured);
}
