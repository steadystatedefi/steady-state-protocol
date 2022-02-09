// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../interfaces/ICollateralFund.sol';
import '../tools/tokens/ERC20Base.sol';
import '../tools/math/WadRayMath.sol';

import '../tools/upgradeability/VersionedInitializable.sol';

import 'hardhat/console.sol';

//import '../tools/tokens/ERC20MintableBase.sol';

//TODO: Change to ERC20MintableBase
contract DepositToken is ERC20Base, VersionedInitializable, IDepositToken {
  ICollateralFund private collateralFund; //TODO: If there will only be 1 Fund per chain, don't want this stored in every clone
  address private underlying;

  uint256 public constant DEPOSIT_TOKEN_REVISION = 0x01;

  function getRevision() internal pure override returns (uint256) {
    return DEPOSIT_TOKEN_REVISION;
  }

  constructor() ERC20Base('null', 'null', 18) {}

  function initialize(
    string memory name,
    string memory symbol,
    address _collateralFund,
    address _underlying
  ) external initializer(DEPOSIT_TOKEN_REVISION) {
    collateralFund = ICollateralFund(_collateralFund);
    underlying = _underlying;
    _initializeERC20(name, symbol, 18);
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
