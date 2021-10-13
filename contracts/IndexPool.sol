// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './interfaces/IProtocol.sol';
import './interfaces/IProtocolPayIn.sol';
import './interfaces/IVirtualReserve.sol';
import './interfaces/IPool.sol';
import './PoolToken.sol';

contract IndexPool {
  IPool[] public members;
  uint256 public collateralizationRatio; //1 = 0.001 (ex: 80000 = 80% so each deposit is multiplied by 1.2)
  mapping(address => uint256) public allocations;
  IERC20 public depositToken;
  PoolToken public poolToken;

  function getPoolValue() external view returns (uint256) {
    uint256 total = 0;
    for (uint256 i = 0; i < members.length; i++) {
      total += members[i].getPoolValue();
    }
  }

  function calculateAdjustedDeposit(uint256 amount, uint256 share) internal view returns (uint256) {
    return (share * amount * (2 * 100000 - collateralizationRatio)) / (100000 * 100000);
  }

  function deposit(uint256 amount) external {
    require(depositToken.allowance(msg.sender, address(this)) >= amount);
    depositToken.transferFrom(msg.sender, address(this), amount);
    for (uint256 i = 0; i < members.length; i++) {
      IPool pool = members[i];
      address addr = address(pool);
      uint256 allocation = allocations[addr];
      //TODO: Instead of depositing immediately, perhaps group together every x deposits in order to save gas
      pool.deposit(calculateAdjustedDeposit(amount, allocation));
    }
    //poolValue += amount;
  }
}
