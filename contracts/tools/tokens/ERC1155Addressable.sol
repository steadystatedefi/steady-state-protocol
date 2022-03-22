// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './ERC1155Supply.sol';
import './IERC1155.sol';
import '../upgradeability/Clones.sol';

///@dev An IERC1155Adaptable is an ERC1155 that can handle transfers by an ERC1155ERC20Adapter
interface IERC1155Adaptable is IERC1155 {
  function transferByAdapter(
    uint256 id,
    address from,
    address recipient,
    uint256 amount
  ) external;

  function totalSupply(uint256 id) external view returns (uint256);

  function exists(uint256 id) external view returns (bool);
}

///@dev ERC1155 that calculates ids based on underlying tokens and their corresponding
/// ERC20 adapter deterministic address
abstract contract ERC1155Addressable is ERC1155Supply {
  event AdapterCreated(address underlying, address adapter);

  address private adapterImplementation;

  mapping(uint256 => address) public idToUnderlying;

  ///@dev Sets the ERC20 adapter address, can only be called once
  function setAdapter(address adapter) internal {
    require(adapterImplementation == address(0));
    adapterImplementation = adapter;
  }

  function getAdapter() internal view returns (address) {
    return adapterImplementation;
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
    require(msg.sender == address(uint160(id)), 'Transfer not by adapter');
    _unsafeTransferFrom(from, recipient, id, amount, '');
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

    _batchMint(to, ids, amounts, data);
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

    _batchBurn(from, ids, amounts);
  }

  ///@dev Calculate the address of the adapter for an underlying (deployed or not)
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

  ///@dev Calculate the address of the adapter for an underlying (deployed or not)
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
  function balanceOfA(address account, address asset) public view returns (uint256) {
    return balanceOf[account][_getId(asset)];
  }

  function numToMint(address underlying, uint256 amount) public view virtual returns (uint256);
}
