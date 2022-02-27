// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';

abstract contract CollateralFundInvesting {
  address public FundManager; //This should be a contract that enforces limits to different strategies

  //TODO: If dToken (ERC1155) will track the amount of underlying (this is different than totalSupply)
  //  then only the invested amount should be stored to avoid extra store
  struct Balance {
    uint128 balance; //Originally amt of deposits, grows with invest reconciliation
    uint128 debt; //balanceOf(this) ~= balance-debt
  }

  mapping(address => Balance) public assetBalances;

  constructor() {
    FundManager = msg.sender;
  }

  function withdrawFund(address asset, uint256 amount) external {
    require(msg.sender == FundManager);
    IERC20(asset).transfer(msg.sender, amount);
  }

  //TODO: Thinking of making this similar to Yearn Strategy?
}
