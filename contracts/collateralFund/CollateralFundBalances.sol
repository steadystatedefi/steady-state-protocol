// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//Name ideas: CollateralFundCollateralStorage, CollateralFundCollateralFactory

//TODO: Look at https://github.com/pelith/erc-1155-adapter/blob/master/contracts/ERC1155Adapter.sol

//TODO: Change import
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol';
import '../tools/upgradeability/Clones.sol';
import './DepositToken.sol';

contract CollateralFundBalances is ERC1155Supply {
  address private depositTokenImplementation;

  mapping(uint256 => address) public idToUnderlying;

  constructor() ERC1155('') {
    depositTokenImplementation = address(new DepositToken());
  }

  function balanceOf(address account, address asset) external view returns (uint256) {
    return balanceOf(account, _getId(asset));
  }

  function mintFor(
    address underlying,
    address to,
    uint256 amount,
    bytes memory data
  ) internal {
    _mint(to, _getId(underlying), amount, data);
  }

  //TODO: Do gas comparison and maybe all mints should call batch to avoid additional code
  function mintForBatch(
    address[] memory underlyings,
    uint256[] memory amounts,
    address to,
    bytes memory data
  ) internal {
    uint256[] memory ids = new uint256[](underlyings.length);
    for (uint256 i = 0; i < underlyings.length; i++) {
      ids[i] = _getId(underlyings[i]);
    }

    _mintBatch(to, ids, amounts, data);
  }

  function burnForBatch(
    address from,
    address[] memory underlyings,
    uint256[] memory amounts
  ) internal {
    uint256[] memory ids = new uint256[](underlyings.length);
    for (uint256 i = 0; i < underlyings.length; i++) {
      ids[i] = _getId(underlyings[i]);
    }

    _burnBatch(from, ids, amounts);
  }

  function createToken(
    address underlying,
    string calldata name,
    string calldata symbol
  ) internal returns (address) {
    bytes32 x;
    assembly {
      x := add(0x0, underlying)
    }
    address clone = Clones.cloneDeterministic(depositTokenImplementation, x);
    DepositToken(clone).initialize(name, symbol, address(this), underlying);
    return clone;
  }

  function _getAddress(address underlying) internal view returns (address) {
    bytes32 x; //TODO: is mload cheaper?
    assembly {
      x := add(0x0, underlying)
    }
    return Clones.predictDeterministicAddress(depositTokenImplementation, x);
  }

  function _getId(address underlying) internal view returns (uint256) {
    return uint160(_getAddress(underlying));
  }

  function getAddress(address underlying) external view returns (address) {
    return _getAddress(underlying);
  }
}
