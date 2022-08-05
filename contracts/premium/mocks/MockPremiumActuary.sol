// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IPremiumActuary.sol';
import '../../interfaces/IPremiumDistributor.sol';

import '../../tools/tokens/IERC20.sol';

contract MockPremiumActuary is IPremiumActuary {
  address public override premiumDistributor;
  address public override collateral;
  uint256 public drawdown;

  mapping(address => uint256) public premiumBurnt;

  constructor(address _distributor, address _collateral) {
    premiumDistributor = _distributor;
    collateral = _collateral;
  }

  function addSource(address source) external {
    IPremiumDistributor(premiumDistributor).registerPremiumSource(source, true);
  }

  function removeSource(address source) external {
    IPremiumDistributor(premiumDistributor).registerPremiumSource(source, false);
  }

  function setDrawdown(uint256 amount) external {
    drawdown = amount;
  }

  function collectDrawdownPremium() external view override returns (uint256 availablePremiumValue) {
    return drawdown;
  }

  function burnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) external override {
    premiumBurnt[account] += value;
    if (drawdownRecepient != address(0)) {
      drawdown -= value;
      IERC20(collateral).transfer(drawdownRecepient, value);
    }
  }

  function callPremiumAllocationUpdated(
    address insured,
    uint256 accumulated,
    uint256 increment,
    uint256 rate
  ) external {
    IPremiumDistributor(premiumDistributor).premiumAllocationUpdated(insured, accumulated, increment, rate);
  }

  function callPremiumAllocationFinished(address source, uint256 increment) external {
    IPremiumDistributor(premiumDistributor).premiumAllocationFinished(source, 0, increment);
  }

  function setRate(address insured, uint256 rate) external {
    IPremiumDistributor(premiumDistributor).premiumAllocationUpdated(insured, 0, 0, rate);
  }
}
