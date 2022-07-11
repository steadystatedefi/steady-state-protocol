// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../insured/InsuredPoolV1.sol';

contract InsuredPoolV2 is InsuredPoolV1 {
  uint256 private constant CONTRACT_REVISION = 2;

  constructor(IAccessController acl, address collateral_) InsuredPoolV1(acl, collateral_) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
