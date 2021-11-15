// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../interfaces/ICollateralFund.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '../tools/math/WadRayMath.sol';

import 'hardhat/console.sol';

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

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal view override {
    if (from == address(0)) {
      //minting
      return;
    }
    (uint256 hf, int256 balance) = collateralFund.healthFactorOf(from);
    require(hf > WadRayMath.ray());
    require(amount < uint256(type(int256).max));
    //TODO: This only works for stable
    require(balance - int256(amount) > 0, 'Would cause negative balance');
  }
}
