// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IJoinable {
  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external;

  // function statusOf(address insured)
}

interface IJoinEvents {
  event JoinRequested(address indexed insured);
  event JoinCancelled(address indexed insured);
  event JoinProcessed(address indexed insured, bool accepted);
  event JoinFailed(address indexed insured, string reason);
}
