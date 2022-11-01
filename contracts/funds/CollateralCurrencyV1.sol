// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../interfaces/ICollateralCurrencyInit.sol';
import './CollateralCurrency.sol';

contract CollateralCurrencyV1 is VersionedInitializable, ICollateralCurrencyInit, CollateralCurrency {
  uint256 private constant CONTRACT_REVISION = 1;

  constructor(IAccessController acl) CollateralCurrency(acl, '', '') {}

  function initializeCollateralCurrency(string memory name_, string memory symbol_) public override initializer(CONTRACT_REVISION) {
    _initializeERC20(name_, symbol_, DECIMALS);
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }
}
