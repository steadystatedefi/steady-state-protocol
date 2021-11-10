// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockStable is ERC20 {
  address private owner;

  constructor() ERC20('Stable', 'STBL') {
    owner = msg.sender;
  }

  function mint(address to, uint256 amount) external returns (bool) {
    require(msg.sender == owner);
    require(totalSupply() + amount < type(uint256).max);

    _mint(to, amount);
    return true;
  }
}
