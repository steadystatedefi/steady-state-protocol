// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//TODO: Change import
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol';
import '../tools/upgradeability/Clones.sol';
import './DepositTokenAdapter.sol';
import './Treasury.sol';

contract CollateralFundBalances is ERC1155Supply, Treasury {
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
  ///@param to          The person receiving the tokens
  ///@param underlying  The underlying being deposited
  ///@param amount      The amount of underlying deposited
  ///@param data        Data to pass along to ERC1155Receiver
  function mintFor(
    address to,
    address underlying,
    uint256 amount,
    bytes memory data
  ) internal {
    amount = this.numToMint(underlying, amount);
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
      amounts[i] = this.numToMint(underlyings[i], amounts[i]);
    }

    _mintBatch(to, ids, amounts, data);
  }

  ///@dev Burn the correct amount of dTokens to redeem the underlying
  ///@param from        The address to burn tokens
  ///@param underlying  The underlying to withdraw
  ///@param amount      The amount of underlying being redeemed
  function burnFor(
    address from,
    address underlying,
    uint256 amount
  ) internal {
    amount = this.numToMint(underlying, amount);
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
  function numToMint(address underlying, uint256 amount) external view returns (uint256) {
    uint256 supply = totalSupply(_getId(underlying));
    if (supply == 0) {
      return amount;
    }
    uint128 x = this.numberOf(underlying);
    return (supply * amount) / x;
  }
}
