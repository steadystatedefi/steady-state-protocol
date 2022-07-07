// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import './ImperpetualPoolBase.sol';

contract ImperpetualPoolV1 is VersionedInitializable, ImperpetualPoolBase, IWeightedPoolInit {
  uint256 private constant CONTRACT_REVISION = 1;
  uint8 internal constant DECIMALS = 18;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    ImperpetualPoolExtension extension,
    address collateral_
  ) ERC20DetailsBase('', '', DECIMALS) ImperpetualPoolBase(acl, unitSize, collateral_, extension) {}

  function initializeWeighted(
    address governor,
    string calldata tokenName,
    string calldata tokenSymbol,
    WeightedPoolParams calldata params
  ) public override initializer(CONTRACT_REVISION) {
    _initializeERC20(tokenName, tokenSymbol, DECIMALS);
    internalSetGovernor(governor);
    internalSetPoolParams(params);
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
