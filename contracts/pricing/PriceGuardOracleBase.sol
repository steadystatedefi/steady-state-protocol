// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../access/AccessHelper.sol';
import './interfaces/IManagedPriceRouter.sol';
import './interfaces/IPriceFeedChainlinkV3.sol';
import './interfaces/IPriceFeedUniswapV2.sol';
import './OracleRouterBase.sol';
import './FuseBox.sol';

contract PriceGuardOracleBase is OracleRouterBase, FuseBox {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  uint8 private constant EF_LIMIT_BREACHED_STICKY = 1 << 0;

  constructor(IAccessController acl, address quote) AccessHelper(acl) OracleRouterBase(quote) {}

  function pullAssetPrice(address asset, uint256 fuseMask) external override returns (uint256) {
    if (asset == getQuoteAsset()) {
      return WadRayMath.WAD;
    }

    (uint256 v, uint8 flags) = internalReadSource(asset);

    if (v == 0) {
      revert Errors.UnknownPriceAsset(asset);
    }

    if (internalHasAnyBlownFuse(fuseMask)) {
      revert Errors.ExcessiveVolatilityLock(fuseMask);
    }

    if (flags & EF_LIMIT_BREACHED != 0) {
      internalSetCustomFlags(asset, 0, EF_LIMIT_BREACHED_STICKY);
      internalBlowFuses(asset);
      v = 0;
    } else if (flags & EF_LIMIT_BREACHED_STICKY != 0) {
      if (internalHasAnyBlownFuse(asset)) {
        v = 0;
      } else {
        internalSetCustomFlags(asset, EF_LIMIT_BREACHED_STICKY, 0);
      }
    }

    return v;
  }

  function attachSource(address asset, bool attach) external override {
    Value.require(asset != address(0));

    uint256 maskUnset = internalGetOwnedFuses(msg.sender);
    uint256 maskSet;
    Access.require(maskUnset != 0);

    if (attach) {
      (maskSet, maskUnset) = (maskUnset, 0);
    }
    internalSetFuses(asset, maskUnset, maskSet);
  }

  function resetSourceGroup() external override {
    uint256 mask = internalGetOwnedFuses(msg.sender);
    if (mask != 0) {
      internalResetFuses(mask);
    }
  }

  function internalResetGroup(uint256 mask) internal override {
    internalResetFuses(mask);
  }

  function internalRegisterGroup(address account, uint256 mask) internal override {
    internalSetOwnedFuses(account, mask);
  }

  function groupsOf(address account) external view override returns (uint256 memberOf, uint256 ownerOf) {
    return (internalGetFuses(account), internalGetOwnedFuses(account));
  }
}
