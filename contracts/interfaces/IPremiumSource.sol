// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IPremiumSource {
  function burnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) external;
}

interface IDynamicPremiumSource is IPremiumSource {
  function collectPremiumValue() external returns (uint256 availablePremiumValue);
}
