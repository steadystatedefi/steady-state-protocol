// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../insured/InsuredPoolV1.sol';
import '../interfaces/IClaimAccessValidator.sol';

contract InsuredPoolV2 is InsuredPoolV1, IClaimAccessValidator {
  uint256 private constant CONTRACT_REVISION = 2;
  mapping(address => bool) public canClaimInsurance;

  constructor(IAccessController acl, address collateral_) InsuredPoolV1(acl, collateral_) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }

  function setClaimInsurance(address user) external {
    canClaimInsurance[user] = true;
  }
}
