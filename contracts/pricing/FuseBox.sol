// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import './interfaces/IManagedPriceRouter.sol';

abstract contract FuseBox {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  mapping(address => uint256) private _fuseOwners;
  mapping(address => uint256) private _fuseMasks;
  uint256 private _fuseBox;

  function internalBlowFuses(address addr) internal returns (bool blown) {
    uint256 mask = _fuseMasks[addr];
    if (mask != 0) {
      uint256 fuseBox = _fuseBox;
      if ((mask &= ~fuseBox) != 0) {
        _fuseBox = mask | fuseBox;
        internalFuseBlown(addr, fuseBox, mask);
      }
      blown = true;
    }
  }

  function internalFuseBlown(
    address addr,
    uint256 fuseBoxBefore,
    uint256 blownFuses
  ) internal virtual {}

  function internalSetFuses(
    address addr,
    uint256 unsetMask,
    uint256 setMask
  ) internal {
    if ((unsetMask = ~unsetMask) != 0) {
      setMask |= _fuseMasks[addr] & unsetMask;
    }
    _fuseMasks[addr] = setMask;
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

  function internalIsOwnerOfAllFuses(address owner, uint256 mask) internal view returns (bool) {
    return mask & ~_fuseOwners[owner] == 0;
  }

  function internalSetOwnedFuses(address owner, uint256 mask) internal {
    _fuseOwners[owner] = mask;
  }
}
