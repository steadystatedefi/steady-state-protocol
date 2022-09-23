// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface ISubBalance {
  function openSubBalance(address account) external;

  function closeSubBalance(address account, uint256 releaseAmount, uint256 transferAmount) external;

  function subBalanceOf(address account, address from) external view returns (uint256);

  function balancesOf(address account) external view returns (uint256 full, uint256 givenOut, uint256 givenIn);
}
