// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';

interface IManagedCollateralCurrency is IERC20 {
  function mint(address account, uint256 amount) external;

  function mintAndTransfer(
    address onBehalf,
    address recepient,
    uint256 amount
  ) external;

  function burn(address account, uint256 amount) external;
}
