// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Allows a governor to provide custom access control checks.
interface IGovernorAccessBitmask {
  /// @dev Delegates access check to a governor. See IRemoteAccessBitmask
  /// @param subject an to get access permissions/roles for
  /// @param filterMask limits a subset of roles to be checked.
  /// @return mask with permissions/roles currently granted.
  /// @return overrides for permissions/roles which should NOT be checked in the AccessController.
  function governorQueryAccessControlMask(address subject, uint256 filterMask) external view returns (uint256 mask, uint256 overrides);
}
