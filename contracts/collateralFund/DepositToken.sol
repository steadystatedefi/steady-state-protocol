// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../interfaces/ICollateralFund.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

//import '../tools/tokens/ERC20MintableBase.sol';

//TODO: Change to ERC20MintableBase
contract DepositToken is ERC20, IDepositToken {
  ICollateralFund private collateralFund;
  address private underlying;

  constructor(
    string memory name,
    string memory symbol,
    address _collateralFund,
    address _underlying
  ) ERC20(name, symbol) {
    collateralFund = ICollateralFund(_collateralFund);
    underlying = _underlying;
  }

  //TODO: Should this be a function? Kirill says this is more expensive for *large* contracts
  modifier onlyCollateralFund() {
    require(msg.sender == address(collateralFund));
    _;
  }

  function mint(address to, uint256 amount) external override onlyCollateralFund {
    _mint(to, amount);
  }

  function burn(uint256 amount) external override onlyCollateralFund {
    _burn(msg.sender, amount);
  }

  function burnFrom(address account, uint256 amount) external override onlyCollateralFund {
    _burn(account, amount);
  }

  function getUnderlying() external view override returns (address) {
    return underlying;
  }

  //TODO: Override transfer to only occur when healthfactor of collateral fund is > 1
}
