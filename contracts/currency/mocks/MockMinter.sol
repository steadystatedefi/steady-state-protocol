// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/upgradeability/VersionedInitializable.sol';
import '../../interfaces/IManagedCollateralCurrency.sol';

contract MockMinter is VersionedInitializable {
  uint256 private constant CONTRACT_REVISION = 1;
  IManagedCollateralCurrency private immutable _collateral;

  constructor(IManagedCollateralCurrency cc) {
    _collateral = cc;
  }

  function getRevision() internal pure override returns (uint256) {
    return CONTRACT_REVISION;
  }

  function mint(address to, uint amount) external {
    _collateral.mint(to, amount);
  }

  function mintAndTransfer(address onBehalf,
    address recepient,
    uint256 mintAmount,
    uint256 balanceAmount
  ) external {
    _collateral.mintAndTransfer(onBehalf, recepient, mintAmount, balanceAmount);
  }

  function burn(address from, uint amount) external {
    _collateral.burn(from, amount);
  }
}
