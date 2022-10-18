// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IRemoteAccessBitmask.sol';
import '../../tools/upgradeability/IProxy.sol';

/// @dev Main registry of permissions and addresses
interface IAccessController is IRemoteAccessBitmask {
  /// @dev returns an address for the given role id, role must be singleton
  /// @param id is an identifier of a role, must be a power of 2
  function getAddress(uint256 id) external view returns (address);

  /// @dev checks when the address has at least one of the roles
  /// @param id is an identifier of a role or a set of roles
  function isAddress(uint256 id, address addr) external view returns (bool);

  /// @dev returns true when the given address is non zero and is either an owner or a temporary admin
  function isAdmin(address) external view returns (bool);

  /// @dev returns an owner
  function owner() external view returns (address);

  /// @dev returns a list of addresses assigned to a role with the given id
  /// @param id is an identifier of a role, must be a power of 2
  /// @return addrList with all known (active) grantees
  function roleHolders(uint256 id) external view returns (address[] memory addrList);
}
