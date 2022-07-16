// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import './interfaces/IManagerPriceOracle.sol';

abstract contract FuseBox {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  mapping(address => uint256) private _fuseOwners;
  mapping(address => uint256) private _fuseMasks;
  uint256 private _fuseBox;

  function internalBlowFuses(address addr) internal {
    uint256 mask = _fuseMasks[addr];
    if (mask != 0) {
      uint256 fuseBox = _fuseBox;
      if ((mask &= ~fuseBox) != 0) {
        _fuseBox = fuseBox | mask;
        internalFuseBlown(addr, fuseBox, mask);
      }
    }
  }

  function internalFuseBlown(
    address addr,
    uint256 fuseBox,
    uint256 blownMask
  ) internal virtual {}

  function internalSetFuses(
    address addr,
    uint256 mask,
    bool attach
  ) internal {
    if (attach) {
      _fuseMasks[addr] |= mask;
    } else {
      _fuseMasks[addr] &= ~mask;
    }
  }

  function internalGetFuses(address addr) internal view returns (uint256) {
    return _fuseMasks[addr];
  }

  function internalHasAnyBlownFuse(uint256 mask) internal view returns (bool) {
    return mask != 0 && (mask & _fuseBox != 0);
  }

  function internalHasAnyBlownFuse(address addr, uint256 mask) internal view returns (bool) {
    if (mask != 0) {
      if ((mask &= _fuseMasks[addr]) != 0) {
        return internalHasAnyBlownFuse(mask);
      }
    }
    return false;
  }

  function internalGetOwnedFuses(address owner) internal view returns (uint256) {
    return _fuseOwners[owner];
  }

  function internalResetFuses(uint256 mask) internal {
    _fuseBox &= ~mask;
  }

  function internalResetFuses(address owner) internal {
    internalResetFuses(_fuseOwners[owner]);
  }

  function internalIsOwnerOfAllFuses(address owner, uint256 mask) internal view returns (bool) {
    return mask & ~_fuseOwners[owner] == 0;
  }

  function internalSetOwnedFuses(
    address owner,
    uint256 mask,
    bool own
  ) internal {
    if (own) {
      _fuseOwners[owner] |= mask;
    } else {
      _fuseOwners[owner] &= ~mask;
    }
  }

  function _onlyFuseOwner(uint256 mask) private view {
    Access.require(internalIsOwnerOfAllFuses(msg.sender, mask));
  }

  modifier onlyFuseOwner(uint256 mask) {
    _onlyFuseOwner(mask);
    _;
  }
}
