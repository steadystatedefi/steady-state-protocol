// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//TODO: Change import
//import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol';
import '../tools/tokens/ERC1155Addressable.sol';
import '../tools/upgradeability/Clones.sol';
import './DepositTokenAdapter.sol';
import './Treasury.sol';

contract CollateralFundBalances is ERC1155Addressable, Treasury {
  constructor() ERC1155Addressable() {
    setAdapter(address(new DepositTokenERC20Adapter()));
  }

  function uri(uint256 id) public view override returns (string memory) {
    return '';
  }

  ///@dev Creates the Token Adapter for the given underlying
  function createToken(
    address underlying,
    string calldata name,
    string calldata symbol
  ) internal returns (address) {
    bytes32 x;
    assembly {
      x := add(0x0, underlying)
    }
    address clone = Clones.cloneDeterministic(getAdapter(), x);
    DepositTokenERC20Adapter(clone).initialize(name, symbol, 18, _getId(underlying), address(this)); //TODO Set to underlying decimals

    emit AdapterCreated(underlying, clone);
    return clone;
  }

  ///@dev The number of underlying tokens redeemable for the given amount of dTokens
  ///@param underlying The underlying asset
  ///@param amount The amount of dTokens to redeem
  function redeemPerToken(address underlying, uint256 amount) external view returns (uint256) {
    uint256 supply = totalSupply(_getId(underlying));
    if (supply < 1) {
      return 0;
    }
    uint128 x = this.numberOf(underlying);
    return (x * amount) / supply;
  }

  ///@dev The number of shares to mint for a given deposit
  ///@param underlying The underlying asset to deposit
  ///@param amount The amount of underlying to deposit
  function numToMint(address underlying, uint256 amount) public view override returns (uint256) {
    uint256 supply = totalSupply(_getId(underlying));
    if (supply == 0) {
      return amount;
    }
    uint128 x = this.numberOf(underlying);
    return (supply * amount) / x;
  }
}
