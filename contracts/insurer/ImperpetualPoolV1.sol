// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ImperpetualPoolBase.sol';

contract ImperpetualPoolV1 is ImperpetualPoolBase, IWeightedPoolInit {
  uint256 private constant CONTRACT_REVISION = 1;
  uint8 internal constant DECIMALS = 18;

  constructor(ImperpetualPoolExtension extension, JoinablePoolExtension joinExtension)
    ERC20DetailsBase('', '', DECIMALS)
    ImperpetualPoolBase(extension, joinExtension)
  {}

  function initializeWeighted(
    address governor_,
    string calldata tokenName,
    string calldata tokenSymbol,
    WeightedPoolParams calldata params
  ) public override initializer(CONTRACT_REVISION) {
    _initializeERC20(tokenName, tokenSymbol, DECIMALS);
    internalSetGovernor(governor_);
    internalSetPoolParams(params);
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
