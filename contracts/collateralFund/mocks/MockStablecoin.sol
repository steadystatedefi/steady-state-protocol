// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockStable is ERC20 {
  address private owner;

  constructor() ERC20('Stable', 'STBL') {
    owner = msg.sender;
  }

  ///@dev Currently anyone can mint
  function mint(address to, uint256 amount) external returns (bool) {
    //require(msg.sender == owner);

    _mint(to, amount);
    return true;
  }
}
