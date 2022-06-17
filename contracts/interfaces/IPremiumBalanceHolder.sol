// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IPremiumBalanceHolder is ICollateralized {
  function burnPremium(
    address account,
    uint256 collateralValue,
    address collateralRecipient
  ) external;
}
