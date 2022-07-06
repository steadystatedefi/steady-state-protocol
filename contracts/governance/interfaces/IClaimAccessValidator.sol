// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IClaimAccessValidator {
  function canClaimInsurance(address) external view returns (bool);
}
