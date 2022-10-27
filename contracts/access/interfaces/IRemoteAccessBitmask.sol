// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IRemoteAccessBitmask {
  /// @dev Returns permissions/roles from the `filterMask` granted to the `subject`.
  /// @param subject an to get access permissions/roles for
  /// @param filterMask limits a subset of roles to be checked. When == 0 then zero is returned when no roles granted, otherwise any non-zero value.
  /// @return permissions/roles currently granted
  function queryAccessControlMask(address subject, uint256 filterMask) external view returns (uint256);
}
