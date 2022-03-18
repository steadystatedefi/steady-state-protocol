// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//TODO: Change import
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol';
import '../upgradeability/Clones.sol';

//import './DepositTokenAdapter.sol';

abstract contract ERC1155Addressable is ERC1155Supply {
  event AdapterCreated(address underlying, address adapter);

  address private adapterImplementation;

  mapping(uint256 => address) public idToUnderlying;

  constructor() ERC1155('') {}

  ///@dev Sets the ERC20 adapter address, can only be called once
  function setAdapter(address adapter) internal {
    require(adapterImplementation == address(0));
    adapterImplementation = adapter;
  }

  function getAdapter() internal view returns (address) {
    return adapterImplementation;
  }

  ///@dev Mints tokens
  ///@param to          The person receiving the tokens
  ///@param underlying  The underlying asset
  ///@param amount      The amount of underlying deposited
  ///@param data        Data to pass along to ERC1155Receiver
  function mintFor(
    address to,
    address underlying,
    uint256 amount,
    bytes memory data
  ) internal {
    amount = numToMint(underlying, amount);
    _mint(to, _getId(underlying), amount, data);
  }

  ///@dev Mint multiple tokens in 1 batch
  function mintForBatch(
    address to,
    address[] memory underlyings,
    uint256[] memory amounts,
    bytes memory data
  ) internal {
    uint256[] memory ids = new uint256[](underlyings.length);
    for (uint256 i = 0; i < underlyings.length; i++) {
      ids[i] = _getId(underlyings[i]);
      amounts[i] = numToMint(underlyings[i], amounts[i]);
    }

    _mintBatch(to, ids, amounts, data);
  }

  ///@dev Burn the correct amount of tokens to redeem the underlying
  ///@param from        The address to burn tokens
  ///@param underlying  The underlying to withdraw
  ///@param amount      The amount of underlying being redeemed
  function burnFor(
    address from,
    address underlying,
    uint256 amount
  ) internal {
    amount = numToMint(underlying, amount);
    _burn(from, _getId(underlying), amount);
  }

  ///@dev Burns multiple tokens in 1 batch
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
  ///@param id        The ID of the token to transfer
  ///@param from      The sender of the tokens
  ///@param recipient The receiver of the tokens
  ///@param amount    Number of tokens to transfer
  function transferByAdapter(
    uint256 id,
    address from,
    address recipient,
    uint256 amount
  ) external {
    require(msg.sender == address(uint160(id)));
    _safeTransferFrom(from, recipient, id, amount, '');
  }

  ///@dev Get what the adapter for an underlying will be
  function _getAddress(address underlying) internal view returns (address) {
    bytes32 x; //TODO: is mload cheaper?
    assembly {
      x := add(0x0, underlying)
    }
    return Clones.predictDeterministicAddress(adapterImplementation, x);
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

  ///@dev Get the total supply of a token given the underlying
  function totalSupply(address asset) external view returns (uint256) {
    return totalSupply(_getId(asset));
  }

  ///@dev Get the balance of an account's token by the underlying address
  function balanceOf(address account, address asset) external view returns (uint256) {
    return balanceOf(account, _getId(asset));
  }

  function numToMint(address underlying, uint256 amount) public view virtual returns (uint256);
}
