// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../PremiumFund.sol';

contract MockPremiumFund is PremiumFund {
  constructor(address collateral_) PremiumFund(collateral_) {}

  modifier onlyAdmin() override {
    _;
  }
}
