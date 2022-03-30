// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralized.sol';

interface IInvestable is ICollateralized {
  function withdrawableAllowance(address account) external view returns (uint256);

  function delegatedInvest(
    address account,
    uint256 amount,
    bytes calldata params
  ) external returns (uint256 acceptedAmount, address reciever);
}
