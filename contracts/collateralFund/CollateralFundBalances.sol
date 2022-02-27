// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//TODO: Change import
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol';
import '../tools/upgradeability/Clones.sol';
import './DepositTokenAdapter.sol';

contract CollateralFundBalances is ERC1155Supply {
  event AdapterCreated(address underlying, address adapter);

  address private depositTokenImplementation;

  mapping(uint256 => address) public idToUnderlying;
  mapping(uint256 => address) public adapters;

  constructor() ERC1155('') {
    depositTokenImplementation = address(new DepositTokenERC20Adapter());
  }

  function balanceOf(address account, address asset) external view returns (uint256) {
    return balanceOf(account, _getId(asset));
  }

  ///@dev Mints dTokens
  function mintFor(
    address to,
    address underlying,
    uint256 amount,
    bytes memory data
  ) internal {
    _mint(to, _getId(underlying), amount, data);
  }

  ///@dev Mint multiple dTokens in 1 batch
  function mintForBatch(
    address to,
    address[] memory underlyings,
    uint256[] memory amounts,
    bytes memory data
  ) internal {
    uint256[] memory ids = new uint256[](underlyings.length);
    for (uint256 i = 0; i < underlyings.length; i++) {
      ids[i] = _getId(underlyings[i]);
    }

    _mintBatch(to, ids, amounts, data);
  }

  ///@dev Burn dTokens
  function burnFor(
    address from,
    address underlying,
    uint256 amount
  ) internal {
    _burn(from, _getId(underlying), amount);
  }

  ///@dev Burns multiple dTokens in 1 batch
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

  ///@dev This is an unsafe function that MUST ONLY be called by the adapter.
  /// Does not check approvals nor that the sender is legitimate
  function transferByAdapter(
    uint256 id,
    address from,
    address recipient,
    uint256 amount
  ) external {
    require(msg.sender == adapters[id]);
    _safeTransferFrom(from, recipient, id, amount, '');
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
    address clone = Clones.cloneDeterministic(depositTokenImplementation, x);
    DepositTokenERC20Adapter(clone).initialize(name, symbol, 18, _getId(underlying), address(this));
    adapters[_getId(underlying)] = clone;

    emit AdapterCreated(underlying, clone);
    return clone;
  }

  ///@dev Get what the adapter for an underlying will be
  function _getAddress(address underlying) internal view returns (address) {
    bytes32 x; //TODO: is mload cheaper?
    assembly {
      x := add(0x0, underlying)
    }
    return Clones.predictDeterministicAddress(depositTokenImplementation, x);
  }

  ///@dev Converts the address of the (non)-existing adapter to a numerical ID
  function _getId(address underlying) internal view returns (uint256) {
    return uint160(_getAddress(underlying));
  }

  ///@dev Get what the adapter for an underlying will be
  function getAddress(address underlying) external view returns (address) {
    return _getAddress(underlying);
  }

  ///@dev Converts the address of the (non)-exisiting adapter to a numerical ID
  function getId(address underlying) external view returns (uint256) {
    return _getId(underlying);
  }
}
