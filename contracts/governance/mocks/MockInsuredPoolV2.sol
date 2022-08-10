// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../insured/InsuredPoolV1.sol';

contract MockInsuredPoolV2 is InsuredPoolV1 {
  uint256 private constant CONTRACT_REVISION = 2;
  mapping(address => bool) private _canClaimInsurance;

  constructor(IAccessController acl, address collateral_) InsuredPoolV1(acl, collateral_) {}

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }

  function canClaimInsurance(address claimedBy) public view virtual override returns (bool) {
    return super.canClaimInsurance(claimedBy) || _canClaimInsurance[claimedBy];
  }

  function setClaimInsurance(address user) external {
    _canClaimInsurance[user] = true;
  }
}
