// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeOwnable.sol';
import '../tools/Errors.sol';
import '../tools/math/BitUtils.sol';
import '../tools/upgradeability/TransparentProxy.sol';
import '../tools/upgradeability/IProxy.sol';
import './interfaces/IAccessController.sol';
import './interfaces/IManagedAccessController.sol';
import './AccessCallHelper.sol';

import 'hardhat/console.sol';

abstract contract AccessControllerBase is SafeOwnable, IManagedAccessController {
  using BitUtils for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  enum AddrMode {
    None,
    /// @dev only one address can be assigned, supports setAddress/getAddress
    Singlet,
    /// @dev only one address can be assigned once, supports setAddress/getAddress
    ProtectedSinglet,
    /// @dev any number of addresses can be granted
    Multilet
  }

  struct AddrInfo {
    address addr;
    AddrMode mode;
  }

  /// @dev a bitmask of roles assigned to an address
  mapping(address => uint256) private _masks;
  /// @dev singlet values by role id
  mapping(uint256 => AddrInfo) private _singlets;
  /// @dev multlet grantees by role id
  mapping(uint256 => EnumerableSet.AddressSet) private _multilets;

  AccessCallHelper private immutable _callHelper;

  /// @dev mask of all roles being singletons
  uint256 private _singletons;

  /// @dev temporary admin
  address private _tempAdmin;
  /// @dev temporary admin expiry
  uint32 private _expiresAt;

  constructor(
    uint256 singletons,
    uint256 nonSingletons,
    uint256 protecteds
  ) {
    require(singletons & nonSingletons == 0, 'mixed types');
    require(singletons & protecteds == protecteds, 'all protected must be singletons');

    for ((uint256 flags, uint256 mask) = (singletons | nonSingletons, 1); flags > 0; (flags, mask) = (flags >> 1, mask << 1)) {
      if (flags & 1 != 0) {
        AddrInfo storage info = _singlets[mask];
        info.mode = nonSingletons & mask != 0 ? AddrMode.Multilet : (protecteds & mask != 0 ? AddrMode.ProtectedSinglet : AddrMode.Singlet);
      }
    }

    _singletons = singletons;

    _callHelper = new AccessCallHelper(address(this));
  }

  function _onlyOwnerOrAdmin() private view {
    Access.require(isAdmin(msg.sender));
  }

  modifier onlyOwnerOrAdmin() {
    _onlyOwnerOrAdmin();
    _;
  }

  function owner() public view override(IAccessController, SafeOwnable) returns (address) {
    return super.owner();
  }

  /// @inheritdoc IAccessController
  function isAdmin(address addr) public view returns (bool) {
    return addr != address(0) && (addr == owner() || (addr == _tempAdmin && _expiresAt > block.timestamp));
  }

  /// @inheritdoc IRemoteAccessBitmask
  function queryAccessControlMask(address addr, uint256 filter) external view override returns (uint256 flags) {
    flags = _masks[addr];
    return filter == 0 ? flags : flags & filter;
  }

  /// @inheritdoc IManagedAccessController
  function setTemporaryAdmin(address admin, uint256 expiryTime) external override onlyOwner {
    if (_tempAdmin != address(0)) {
      _revokeAllRoles(_tempAdmin);
    }
    if ((_tempAdmin = admin) != address(0)) {
      Arithmetic.require((_expiresAt = uint32(expiryTime += block.timestamp)) >= block.timestamp);
    } else {
      _expiresAt = 0;
      expiryTime = 0;
    }
    emit TemporaryAdminAssigned(admin, expiryTime);
  }

  /// @inheritdoc IManagedAccessController
  function getTemporaryAdmin() external view override returns (address admin, uint256 expiresAt) {
    admin = _tempAdmin;
    if (admin != address(0)) {
      return (admin, _expiresAt);
    }
    return (address(0), 0);
  }

  /// @inheritdoc IManagedAccessController
  function renounceTemporaryAdmin() external override {
    address tempAdmin = _tempAdmin;
    if (tempAdmin == address(0)) {
      return;
    }
    if (msg.sender != tempAdmin && _expiresAt > block.timestamp) {
      return;
    }
    _revokeAllRoles(tempAdmin);
    _tempAdmin = address(0);
    emit TemporaryAdminAssigned(address(0), 0);
  }

  /// @dev grants roles to the address
  /// @param flags a role id or a combined bitmask of multiple roles, singlets are not allowed
  function grantRoles(address addr, uint256 flags) external onlyOwnerOrAdmin returns (uint256) {
    return _grantMultiRoles(addr, flags, true);
  }

  function _grantMultiRoles(
    address addr,
    uint256 flags,
    bool strict
  ) internal returns (uint256) {
    uint256 m = _masks[addr];
    flags &= ~m;
    if (flags == 0) {
      return m;
    }
    m |= flags;
    _masks[addr] = m;

    for (uint256 mask = 1; flags > 0; (flags, mask) = (flags >> 1, mask << 1)) {
      if (flags & 1 != 0) {
        AddrInfo storage info = _singlets[mask];
        if (info.addr != addr) {
          AddrMode mode = info.mode;
          if (mode == AddrMode.None) {
            info.mode = AddrMode.Multilet;
          } else {
            require(mode == AddrMode.Multilet || !strict, 'singleton should use setAddress');
          }

          _multilets[mask].add(addr);
        }
      }
    }

    emit RolesUpdated(addr, m);
    return m;
  }

  /// @dev revokes roles from the address
  /// @param flags a role id or a combined bitmask of multiple roles, singlets are not allowed
  function revokeRoles(address addr, uint256 flags) external onlyOwnerOrAdmin returns (uint256) {
    return _revokeRoles(addr, flags);
  }

  /// @dev revokes all roles from the address. Will revert when a protected singlet role is present
  function revokeAllRoles(address addr) external onlyOwnerOrAdmin returns (uint256) {
    return _revokeAllRoles(addr);
  }

  function _revokeAllRoles(address addr) private returns (uint256) {
    uint256 m = _masks[addr];
    if (m == 0) {
      return 0;
    }
    delete _masks[addr];
    _revokeRolesByMask(addr, m);
    emit RolesUpdated(addr, 0);
    return m;
  }

  function _revokeRolesByMask(address addr, uint256 flags) private {
    for (uint256 mask = 1; flags > 0; (flags, mask) = (flags >> 1, mask << 1)) {
      if (flags & 1 != 0) {
        AddrInfo storage info = _singlets[mask];
        if (info.addr == addr) {
          _ensureNotProtected(info.mode);
          info.addr = address(0);
          emit AddressSet(mask, address(0));
        } else {
          _multilets[mask].remove(addr);
        }
      }
    }
  }

  function _ensureNotProtected(AddrMode mode) private pure {
    require(mode != AddrMode.ProtectedSinglet, 'protected singleton can not be revoked');
  }

  function _revokeRoles(address addr, uint256 flags) private returns (uint256) {
    uint256 m = _masks[addr];
    if ((flags &= m) != 0) {
      _masks[addr] = (m &= ~flags);
      _revokeRolesByMask(addr, flags);
      emit RolesUpdated(addr, m);
    }
    return m;
  }

  /// @dev revokes given roles from all grantees.
  /// @dev Singlets are always revoked, while number grantees of multi-assing roles are limited by `limitMultilets`
  /// @param flags a role id or a combined bitmask of multiple roles, protected singlets will revert
  /// @param limitMultilets a max number of grantees of multi-assinged roles to be revoked (to control gas requirement)
  /// @return all is true when all grantees for the given roles were revoked
  function revokeRolesFromAll(uint256 flags, uint256 limitMultilets) external onlyOwnerOrAdmin returns (bool all) {
    all = true;
    uint256 fullMask = flags;

    for (uint256 mask = 1; flags > 0; (flags, mask) = (flags >> 1, mask << 1)) {
      if (flags & 1 != 0) {
        AddrInfo storage info = _singlets[mask];
        address addr = info.addr;
        if (addr != address(0)) {
          _ensureNotProtected(info.mode);
          _masks[addr] &= ~mask;
          info.addr = address(0);
          emit AddressSet(mask, address(0));
        }

        if (all) {
          EnumerableSet.AddressSet storage multilets = _multilets[mask];
          for (uint256 j = multilets.length(); j > 0; ) {
            j--;
            if (limitMultilets == 0) {
              all = false;
              break;
            }
            limitMultilets--;
            _revokeRoles(multilets.at(j), fullMask);
          }
        }
      }
    }
  }

  function _onlyOneRole(uint256 id) private pure {
    require(id.isPowerOf2nz(), 'only one role is allowed');
  }

  /// @inheritdoc IAccessController
  function roleHolders(uint256 id) external view override returns (address[] memory addrList) {
    _onlyOneRole(id);

    address singleton = _singlets[id].addr;
    EnumerableSet.AddressSet storage multilets = _multilets[id];

    if (singleton == address(0) || multilets.contains(singleton)) {
      return multilets.values();
    }

    addrList = new address[](1 + multilets.length());
    addrList[0] = singleton;

    for (uint256 i = addrList.length; i > 1; ) {
      i--;
      addrList[i] = multilets.at(i - 1);
    }
  }

  /// @inheritdoc IManagedAccessController
  function setAddress(uint256 id, address newAddress) public override onlyOwnerOrAdmin {
    _internalSetAddress(id, newAddress);
    emit AddressSet(id, newAddress);
  }

  function _internalSetAddress(uint256 id, address newAddress) private {
    _onlyOneRole(id);

    AddrInfo storage info = _singlets[id];
    AddrMode mode = info.mode;

    if (mode == AddrMode.None) {
      _singletons |= id;
      info.mode = AddrMode.Singlet;
    } else {
      require(mode < AddrMode.Multilet, 'id is not a singleton');

      address prev = info.addr;
      if (prev != address(0)) {
        require(mode == AddrMode.Singlet, 'id is protected');
        _masks[prev] = _masks[prev] & ~id;
      }
    }
    if (newAddress != address(0)) {
      require(Address.isContract(newAddress), 'must be contract');
      _masks[newAddress] = _masks[newAddress] | id;
    }
    info.addr = newAddress;
  }

  /// @inheritdoc IAccessController
  function getAddress(uint256 id) public view override returns (address addr) {
    AddrInfo storage info = _singlets[id];

    if ((addr = info.addr) == address(0)) {
      _onlyOneRole(id);
      require(info.mode < AddrMode.Multilet, 'id is not a singleton');
    }
    return addr;
  }

  /// @inheritdoc IAccessController
  function isAddress(uint256 id, address addr) public view override returns (bool) {
    return _masks[addr] & id != 0;
  }

  /// @dev sets a singlet type for the given role. Reverts when the role is multilet.
  /// @param id is an identifier of a role, must be a power of 2
  /// @param protection when is true will cobfigure the role as a protected singlet, otherwise as a regular singlet
  function setProtection(uint256 id, bool protection) external onlyOwnerOrAdmin {
    _onlyOneRole(id);
    AddrInfo storage info = _singlets[id];
    require(info.mode < AddrMode.Multilet, 'id is not a singleton');
    info.mode = protection ? AddrMode.ProtectedSinglet : AddrMode.Singlet;
  }

  function _callWithRoles(
    uint256 flags,
    address grantAddr,
    function(address, bytes calldata) internal returns (bytes memory) callFn,
    address callAddr,
    bytes calldata data
  ) private returns (bytes memory result) {
    require(callAddr != address(this) && Address.isContract(callAddr), 'must be another contract');

    (bool restoreMask, uint256 oldMask) = _beforeCallWithRoles(flags, grantAddr);

    result = callFn(callAddr, data);

    if (restoreMask) {
      _masks[grantAddr] = oldMask;
      emit RolesUpdated(grantAddr, oldMask);
    }
    return result;
  }

  function _directCall(address callAddr, bytes calldata callData) private returns (bytes memory) {
    return Address.functionCall(callAddr, callData);
  }

  function _indirectCall(address callAddr, bytes calldata callData) private returns (bytes memory) {
    return _callHelper.doCall(callAddr, callData);
  }

  function ensureNoSingletons() internal virtual {
    revert('singleton should use setAddress');
  }

  function _beforeCallWithRoles(uint256 flags, address addr) private returns (bool restoreMask, uint256 oldMask) {
    if (_singletons & flags != 0) {
      ensureNoSingletons();
    }

    oldMask = _masks[addr];
    if (flags & ~oldMask != 0) {
      flags |= oldMask;
      emit RolesUpdated(addr, flags);
      _masks[addr] = flags;

      restoreMask = true;
    }
  }

  /// @inheritdoc IManagedAccessController
  function directCallWithRoles(
    uint256 flags,
    address addr,
    bytes calldata data
  ) external override onlyOwnerOrAdmin returns (bytes memory result) {
    return _callWithRoles(flags, addr, _directCall, addr, data);
  }

  /// @inheritdoc IManagedAccessController
  function directCallWithRolesBatch(CallParams[] calldata params) external override onlyOwnerOrAdmin returns (bytes[] memory results) {
    results = new bytes[](params.length);

    for (uint256 i = 0; i < params.length; i++) {
      address callAddr = params[i].callAddr == address(0) ? getAddress(params[i].callFlag) : params[i].callAddr;
      results[i] = _callWithRoles(params[i].accessFlags, callAddr, _directCall, callAddr, params[i].callData);
    }
    return results;
  }

  /// @inheritdoc IManagedAccessController
  function callWithRolesBatch(CallParams[] calldata params) external override onlyOwnerOrAdmin returns (bytes[] memory results) {
    results = new bytes[](params.length);

    for (uint256 i = 0; i < params.length; i++) {
      address callAddr = params[i].callAddr == address(0) ? getAddress(params[i].callFlag) : params[i].callAddr;
      results[i] = _callWithRoles(params[i].accessFlags, address(_callHelper), _indirectCall, callAddr, params[i].callData);
    }
    return results;
  }
}
