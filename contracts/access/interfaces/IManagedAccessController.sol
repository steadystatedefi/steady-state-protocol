// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IRemoteAccessBitmask.sol';
import './IAccessController.sol';

/// @dev Management interface for the registry of permissions and addresses
interface IManagedAccessController is IAccessController {
  /// @dev Revokes all permissions assinged to the previous temporaty admin and assigns a new one. Only owner can call
  /// @dev A temporary admin can assign roles like an owner, but is unable to change ownership or assign another temporary admin.
  /// @dev There can be only one temporary admin, changing an admin will revoke all self-assigned permission.
  /// @dev After expiry, the assigned admin will not be recognized by isAdmin() function,
  /// @dev but self-assigned permission will stay valid until renounceTemporaryAdmin() or setTemporaryAdmin().
  /// @dev NB! Permissions assigned by the temorary admin to other addresses will not be revoked.
  /// @param admin an address to become an admin, can be zero
  /// @param expirySeconds a number of seconds for this assigment to be valid. Ignored when admin param is zero.
  function setTemporaryAdmin(address admin, uint256 expirySeconds) external;

  /// @dev Returns a valid (non expired) temporary admin address and timestamp of its expiry.
  function getTemporaryAdmin() external view returns (address admin, uint256 expiresAt);

  /// @dev Unsets temporary admin and revokes its self-assigned permission.
  /// @dev The temporary admin can call it at any time.
  /// @dev And any can call it after expiry, but calling it before expiry will be ignored. Doesnt revert.
  function renounceTemporaryAdmin() external;

  /// @dev Sets a signleton address for a role with the given id.
  /// @dev Calling with id of a multi-assignable role will revert.
  /// @dev Calling with id of a protected singleton role may revert when the role was already assigned.
  /// @param id - identifier of a role, must be a power of 2
  /// @param newAddress - an address to be set.
  function setAddress(uint256 id, address newAddress) external;

  struct CallParams {
    /// @dev Roles to be assigned to a caller
    uint256 accessFlags;
    /// @dev When callAddr is zero, it will be evaluated as getAddress(callFlag)
    uint256 callFlag;
    /// @dev An address to be called
    address callAddr;
    /// @dev Encoded call data
    bytes callData;
  }

  /// @dev Perform the given calls through an AccessCallHelper, roles are assigned to the AccessCallHelper.
  /// @dev Each entry of params is handled separatly, assignment of roles is restored after each call.
  /// @return result with return values of calls made.
  function callWithRolesBatch(CallParams[] calldata params) external returns (bytes[] memory result);

  /// @dev Assignes the given roles to this controller itself and makes the call. Role assignments are restored afre the call.
  /// @param flags a set of roles to be assigned before the call
  /// @param addr a contract to be called
  /// @param data encoded call data
  /// @return result with return value of the call made.
  function directCallWithRoles(
    uint256 flags,
    address addr,
    bytes calldata data
  ) external returns (bytes memory result);

  /// @dev Perform the given calls through this controller, roles are assigned to this controller.
  /// @dev Each entry of params is handled separatly, assignment of roles is restored after each call.
  /// @return result with return values of calls made.
  function directCallWithRolesBatch(CallParams[] calldata params) external returns (bytes[] memory result);

  event AddressSet(uint256 indexed id, address indexed newAddress);
  event RolesUpdated(address indexed addr, uint256 flags);
  event TemporaryAdminAssigned(address indexed admin, uint256 expiresAt);
  event AnyRoleModeEnabled();
  event AnyRoleModeBlocked();
}
