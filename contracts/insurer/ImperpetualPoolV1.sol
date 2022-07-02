// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import './ImperpetualPoolBase.sol';

contract ImperpetualPoolV1 is VersionedInitializable, ImperpetualPoolBase {
  uint256 private constant CONTRACT_REVISION = 1;
  uint8 internal constant DECIMALS = 18;

  constructor(
    uint256 unitSize,
    ImperpetualPoolExtension extension,
    address collateral_
  ) ERC20DetailsBase('', '', DECIMALS) ImperpetualPoolBase(unitSize, extension) Collateralized(collateral_) {
    // _joinHandler = address(this);
    // internalSetPoolParams(
    //   WeightedPoolParams({
    //     maxAdvanceUnits: 10000,
    //     minAdvanceUnits: 1000,
    //     riskWeightTarget: 1000, // 10%
    //     minInsuredShare: 100, // 1%
    //     maxInsuredShare: 4000, // 25%
    //     minUnitsPerRound: 20,
    //     maxUnitsPerRound: 20,
    //     overUnitsPerRound: 30,
    //     maxDrawdownInverse: 9000 // 90%
    //   })
    // );
  }

  function initializeToken(
    address acl,
    string calldata tokenName,
    string calldata tokenSymbol
  ) public initializer(CONTRACT_REVISION) {
    _initializeERC20(tokenName, tokenSymbol, DECIMALS);
    acl;
    // setRemoteAcl(acl);
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
