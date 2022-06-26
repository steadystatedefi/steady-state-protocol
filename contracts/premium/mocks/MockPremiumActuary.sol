// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IPremiumActuary.sol';
import '../../interfaces/IPremiumDistributor.sol';

import '../../tools/tokens/IERC20.sol';

contract MockPremiumActuary is IPremiumActuary {
  address public premiumDistributor;
  address public collateral;

  constructor(address _distributor, address _collateral) {
    premiumDistributor = _distributor;
    collateral = _collateral;
  }

  function addSource(address source) external {
    IPremiumDistributor(premiumDistributor).registerPremiumSource(source, true);
  }

  function collectDrawdownPremium() external returns (uint256 availablePremiumValue) {
    availablePremiumValue = 0;
  }

  function burnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) external {}

  function callPremiumAllocationUpdated(
    address insured,
    uint256 accumulated,
    uint256 increment,
    uint256 rate
  ) external {
    IPremiumDistributor(premiumDistributor).premiumAllocationUpdated(insured, accumulated, increment, rate);
  }

  function setRate(address insured, uint256 rate) external {
    IPremiumDistributor(premiumDistributor).premiumAllocationUpdated(insured, 0, 0, rate);
  }
}
