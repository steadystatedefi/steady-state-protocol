// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './MockImperpetualPool.sol';

contract MockCancellableImperpetualPool is MockImperpetualPool {
  constructor(ImperpetualPoolExtension extension, JoinablePoolExtension joinExtension) MockImperpetualPool(extension, joinExtension) {}

  function handleJoinRequest(address) external pure override returns (MemberStatus) {
    return MemberStatus.Joining;
  }
}
