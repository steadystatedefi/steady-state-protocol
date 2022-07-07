// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IRemoteAccessBitmask.sol';
import './IAccessController.sol';

interface IManagedAccessController is IAccessController {
  function setTemporaryAdmin(address admin, uint256 expirySeconds) external;

  function getTemporaryAdmin() external view returns (address admin, uint256 expiresAt);

  function renounceTemporaryAdmin() external;

  function setAddress(uint256 id, address newAddress) external;

  struct CallParams {
    uint256 accessFlags;
    uint256 callFlag;
    address callAddr;
    bytes callData;
  }

  function callWithRolesBatch(CallParams[] calldata params) external returns (bytes[] memory result);

  function directCallWithRoles(
    uint256 flags,
    address addr,
    bytes calldata data
  ) external returns (bytes memory result);

  function directCallWithRolesBatch(CallParams[] calldata params) external returns (bytes[] memory result);

  event AddressSet(uint256 indexed id, address indexed newAddress);
  event RolesUpdated(address indexed addr, uint256 flags);
  event TemporaryAdminAssigned(address indexed admin, uint256 expiresAt);
  event AnyRoleModeEnabled();
  event AnyRoleModeBlocked();
}
