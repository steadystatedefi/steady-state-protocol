// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../reinvest/AaveTypes.sol';
import '../../tools/tokens/IERC20.sol';

interface IERC20Mintable is IERC20 {
  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;
}

///@dev Does not check underlying asset passed to calls is correct
contract MockAavePoolV3 is IAaveLendingPoolV3 {
  IERC20Mintable private aToken;

  constructor(IERC20Mintable aToken_) {
    aToken = aToken_;
  }

  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16
  ) external {
    aToken.mint(onBehalfOf, amount);
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external returns (uint256) {
    aToken.burn(msg.sender, amount);
    IERC20(asset).transfer(to, amount);
    return amount;
  }

  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {}

  function getReserveData(address) external view returns (AaveDataTypes.ReserveDataV3 memory data) {
    data.aTokenAddress = address(aToken);
  }

  function addYieldToUser(address to, uint256 amount) external {
    aToken.mint(to, amount);
  }
}
