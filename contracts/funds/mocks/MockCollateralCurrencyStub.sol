// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/tokens/IERC20.sol';
import '../../tools/tokens/IERC1363.sol';

contract MockCollateralCurrencyStub {
  function invest(address insurer, uint256 amount) external {
    _transferAndCall(insurer, amount, '');
  }

  function approve(address, uint256) external pure returns (bool) {
    return true;
  }

  function allowance(address, address) external view returns (uint256) {}

  function balanceOf(address) external view returns (uint256) {}

  function totalSupply() external view returns (uint256) {}

  function transfer(address, uint256) external pure returns (bool) {
    return true;
  }

  function transferAndCall(address to, uint256 value) external returns (bool) {
    return _transferAndCall(to, value, '');
  }

  function transferAndCall(
    address to,
    uint256 value,
    bytes memory data
  ) external returns (bool) {
    return _transferAndCall(to, value, data);
  }

  function _transferAndCall(
    address to,
    uint256 value,
    bytes memory data
  ) private returns (bool) {
    ERC1363.callReceiver(to, msg.sender, msg.sender, value, data);
    return true;
  }

  function borrowManager() public view returns (address) {}
}
