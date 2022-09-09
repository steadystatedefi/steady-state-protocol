// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IPremiumActuary is ICollateralized {
  function premiumDistributor() external view returns (address);

  function collectDrawdownPremium() external returns (uint256 maxDrawdownValue, uint256 availableDrawdownValue);

  function burnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) external;
}
