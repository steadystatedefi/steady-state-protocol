// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev both the protocol identity for SST and metadata provider
interface IProtocol {
  function getSeqId() external view returns (uint256);

  function getName() external view returns (string memory);

  /// @dev returns true when the given sender is allowed as the given role for this protocol
  function hasRole(address sender, uint256 roleFlag) external view returns (bool);
}
