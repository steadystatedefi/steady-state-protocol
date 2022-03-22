// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//import '../tools/tokens/ERC20BalancelessBase.sol';
import '../tools/tokens/ERC20Base.sol';
//import '../tools/tokens/ERC20MintableBase.sol';
import '../tools/SafeOwnable.sol';

interface ICollateralFundTransferCheck {
  function beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) external;

  function afterTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) external;
}

contract CoverageCurrency is ERC20Base, SafeOwnable {
  // Should be the collateral fund, which can move anyones CC at will
  // Does not allow changing with ownable - but maybe should approve?
  address public collateralFund;

  constructor(
    string memory _n,
    string memory _s,
    uint8 _d,
    address cf
  ) ERC20Base(_n, _s, _d) {
    collateralFund = cf;
  }

  function mint(address account, uint256 amount) external onlyOwner {
    if (allowance(account, collateralFund) == 0) {
      _approve(account, collateralFund, type(uint256).max);
    }
    _mint(account, amount);
  }

  function burn(address account, uint256 amount) external onlyOwner {
    _burn(account, amount);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    ICollateralFundTransferCheck(collateralFund).beforeTokenTransfer(from, to, amount);
  }

  function _afterTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    ICollateralFundTransferCheck(collateralFund).afterTokenTransfer(from, to, amount);
  }
}
