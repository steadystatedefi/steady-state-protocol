// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Minimalist and gas efficient standard ERC1155 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
///
/// Steady State modifications:
///   - Call _beforeTokenTransfer() hook before all transfers
///   - Create an unsafe transfer method to be used by ERC20 adapters

abstract contract ERC1155 {
  /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

  event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);

  event TransferBatch(
    address indexed operator,
    address indexed from,
    address indexed to,
    uint256[] ids,
    uint256[] amounts
  );

  event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

  event URI(string value, uint256 indexed id);

  /*///////////////////////////////////////////////////////////////
                            ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

  mapping(address => mapping(uint256 => uint256)) public balanceOf;

  mapping(address => mapping(address => bool)) public isApprovedForAll;

  /*///////////////////////////////////////////////////////////////
                             METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

  function uri(uint256 id) public view virtual returns (string memory);

  /*///////////////////////////////////////////////////////////////
                             ERC1155 LOGIC
    //////////////////////////////////////////////////////////////*/

  /*
    function balanceOf(address a, uint256 u) public view returns (uint256) {
    return balanceOf[a][u];
  }
  */

  function setApprovalForAll(address operator, bool approved) public virtual {
    isApprovedForAll[msg.sender][operator] = approved;

    emit ApprovalForAll(msg.sender, operator, approved);
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) public virtual {
    require(msg.sender == from || isApprovedForAll[from][msg.sender], 'NOT_AUTHORIZED');

    _beforeTokenTransfer(msg.sender, from, to, _asArray(id), _asArray(amount), data);
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;

    emit TransferSingle(msg.sender, from, to, id, amount);

    require(
      to.code.length == 0
        ? to != address(0)
        : ERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, amount, data) ==
          ERC1155TokenReceiver.onERC1155Received.selector,
      'UNSAFE_RECIPIENT'
    );
  }

  ///@dev This function is to ONLY be called from a caller that has checked sender ownership/allowance
  /// This will also NOT call the ERC1155TokenReceiver
  function _unsafeTransferFrom(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) internal {
    //require(msg.sender == from || isApprovedForAll[from][msg.sender], 'NOT_AUTHORIZED');

    _beforeTokenTransfer(msg.sender, from, to, _asArray(id), _asArray(amount), data);
    balanceOf[from][id] -= amount;
    balanceOf[to][id] += amount;

    emit TransferSingle(msg.sender, from, to, id, amount);
  }

  function safeBatchTransferFrom(
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) public virtual {
    uint256 idsLength = ids.length; // Saves MLOADs.

    require(idsLength == amounts.length, 'LENGTH_MISMATCH');

    require(msg.sender == from || isApprovedForAll[from][msg.sender], 'NOT_AUTHORIZED');

    _beforeTokenTransfer(msg.sender, from, to, ids, amounts, data);

    // Storing these outside the loop saves ~15 gas per iteration.
    uint256 id;
    uint256 amount;

    for (uint256 i = 0; i < idsLength; ) {
      id = ids[i];
      amount = amounts[i];

      balanceOf[from][id] -= amount;
      balanceOf[to][id] += amount;

      // An array can't have a total length
      // larger than the max uint256 value.
      unchecked {
        ++i;
      }
    }

    emit TransferBatch(msg.sender, from, to, ids, amounts);

    require(
      to.code.length == 0
        ? to != address(0)
        : ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) ==
          ERC1155TokenReceiver.onERC1155BatchReceived.selector,
      'UNSAFE_RECIPIENT'
    );
  }

  function balanceOfBatch(address[] memory owners, uint256[] memory ids)
    public
    view
    virtual
    returns (uint256[] memory balances)
  {
    uint256 ownersLength = owners.length; // Saves MLOADs.

    require(ownersLength == ids.length, 'LENGTH_MISMATCH');

    balances = new uint256[](ownersLength);

    // Unchecked because the only math done is incrementing
    // the array index counter which cannot possibly overflow.
    unchecked {
      for (uint256 i = 0; i < ownersLength; ++i) {
        balances[i] = balanceOf[owners[i]][ids[i]];
      }
    }
  }

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal virtual {}

  /*///////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
      interfaceId == 0xd9b67a26 || // ERC165 Interface ID for ERC1155
      interfaceId == 0x0e89341c; // ERC165 Interface ID for ERC1155MetadataURI
  }

  /*///////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

  function _mint(
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) internal virtual {
    _beforeTokenTransfer(msg.sender, address(0), to, _asArray(id), _asArray(amount), data);
    balanceOf[to][id] += amount;

    emit TransferSingle(msg.sender, address(0), to, id, amount);

    require(
      to.code.length == 0
        ? to != address(0)
        : ERC1155TokenReceiver(to).onERC1155Received(msg.sender, address(0), id, amount, data) ==
          ERC1155TokenReceiver.onERC1155Received.selector,
      'UNSAFE_RECIPIENT'
    );
  }

  function _batchMint(
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal virtual {
    uint256 idsLength = ids.length; // Saves MLOADs.

    require(idsLength == amounts.length, 'LENGTH_MISMATCH');

    _beforeTokenTransfer(msg.sender, address(0), to, ids, amounts, data);
    for (uint256 i = 0; i < idsLength; ) {
      balanceOf[to][ids[i]] += amounts[i];

      // An array can't have a total length
      // larger than the max uint256 value.
      unchecked {
        ++i;
      }
    }

    emit TransferBatch(msg.sender, address(0), to, ids, amounts);

    require(
      to.code.length == 0
        ? to != address(0)
        : ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, address(0), ids, amounts, data) ==
          ERC1155TokenReceiver.onERC1155BatchReceived.selector,
      'UNSAFE_RECIPIENT'
    );
  }

  function _batchBurn(
    address from,
    uint256[] memory ids,
    uint256[] memory amounts
  ) internal virtual {
    uint256 idsLength = ids.length; // Saves MLOADs.

    require(idsLength == amounts.length, 'LENGTH_MISMATCH');

    _beforeTokenTransfer(msg.sender, from, address(0), ids, amounts, '');
    for (uint256 i = 0; i < idsLength; ) {
      balanceOf[from][ids[i]] -= amounts[i];

      // An array can't have a total length
      // larger than the max uint256 value.
      unchecked {
        ++i;
      }
    }

    emit TransferBatch(msg.sender, from, address(0), ids, amounts);
  }

  function _burn(
    address from,
    uint256 id,
    uint256 amount
  ) internal virtual {
    _beforeTokenTransfer(msg.sender, from, address(0), _asArray(id), _asArray(amount), '');
    balanceOf[from][id] -= amount;

    emit TransferSingle(msg.sender, from, address(0), id, amount);
  }

  function _asArray(uint256 element) private pure returns (uint256[] memory) {
    uint256[] memory array = new uint256[](1);
    array[0] = element;

    return array;
  }
}

/// @notice A generic interface for a contract which properly accepts ERC1155 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
interface ERC1155TokenReceiver {
  function onERC1155Received(
    address operator,
    address from,
    uint256 id,
    uint256 amount,
    bytes calldata data
  ) external returns (bytes4);

  function onERC1155BatchReceived(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes calldata data
  ) external returns (bytes4);
}